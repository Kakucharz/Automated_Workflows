"""These functions run, but their decisions need repair. Read SCHEMA_CONTRACT.md."""

STATES = ('ready', 'complete', 'blocked', 'unresolved', 'failed')


def classify_member(context):
    """Return {'state', 'reason'} for one member, checking evidence in priority order."""
    # 1. A running attempt needs attention first, even if an older result exists.
    if context.get('active_attempt'):
        attempt = context['active_attempt'].get('attempt_id', 'unknown')
        return {'state': 'unresolved',
                'reason': f'Attempt {attempt} is still recorded as running; establish whether it stopped, then reconcile'}
    # 2. A verified output is complete, even if inputs moved or the budget is used up.
    if context.get('verified_result'):
        return {'state': 'complete', 'reason': 'A succeeded attempt has a verified output'}
    # 3. Invalid inputs need investigation; a retry would not fix them.
    if context.get('validation_error'):
        return {'state': 'failed', 'reason': 'Input validation failed: ' + str(context['validation_error'])}
    # 4. Missing input bytes: blocked, and no attempt is spent.
    if context.get('missing_inputs'):
        return {'state': 'blocked',
                'reason': 'Input unavailable for role(s): ' + ', '.join(context['missing_inputs'])}
    # 5. The budget counts non-reused attempts across all batches and restarts.
    if context['attempts_used'] >= context['max_attempts']:
        return {'state': 'failed',
                'reason': f"Attempt budget exhausted ({context['attempts_used']} of {context['max_attempts']})"}
    # 6. An ordinary application failure needs investigation, not a blind retry.
    last = context.get('last_attempt')
    if last and last.get('status') == 'failed':
        return {'state': 'failed',
                'reason': f"Previous attempt failed ({last.get('error_code')}); investigate before retrying"}
    # 7. Verified inputs and budget left (including after a reconciled interruption).
    return {'state': 'ready', 'reason': 'Inputs verified and the attempt budget permits a new attempt'}


def _positive_int(value):
    return isinstance(value, int) and not isinstance(value, bool) and value > 0


def _nonempty_text(value):
    return isinstance(value, str) and bool(value.strip())


def verify_result(member, evidence):
    """True only if every piece of evidence is present and matches this request."""
    if not isinstance(evidence, dict):
        return False
    if evidence.get('request_id') != member.get('request_id') or not _nonempty_text(member.get('request_id')):
        return False
    if not (_nonempty_text(evidence.get('attempt_id')) and _nonempty_text(evidence.get('artifact_id'))):
        return False
    size = evidence.get('size_bytes')
    if not _positive_int(size) or evidence.get('actual_size_bytes') != size:
        return False
    sha = evidence.get('sha256')
    if not (isinstance(sha, str) and len(sha) == 64) or evidence.get('actual_sha256') != sha:
        return False
    # Explicit flags: a missing or non-True value must not pass.
    return all(evidence.get(flag) is True for flag in
               ('catalogue_link_verified', 'grid_verified', 'provenance_verified'))


def summarize_batch(rows):
    """Count each expected member once, using its newest observation."""
    latest = {}
    for row in rows:
        member = row['member_id']
        oid = row['observation_id'] if row['observation_id'] is not None else -1
        if member not in latest or oid > latest[member][0]:
            latest[member] = (oid, row['state'])
    counts = {state: 0 for state in (*STATES, 'unobserved')}
    members = {state: [] for state in counts}
    for member, (oid, state) in latest.items():
        label = 'unobserved' if state is None else state
        if label not in counts:
            raise ValueError(f'Unknown observation state for {member}: {state}')
        counts[label] += 1
        members[label].append(member)
    for label in members:
        members[label].sort()
    return {'expected': len(latest), 'counts': counts, 'members': members}