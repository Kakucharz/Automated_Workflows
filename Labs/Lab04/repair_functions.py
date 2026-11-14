"""Three plausible implementations to investigate and repair. No syntax puzzles."""
import hashlib
import json
import math
import numpy as np

POLICY = 'exact_environment_v1'
INPUT_FIELDS = ('artifact_id', 'sha256', 'size_bytes', 'raster', 'lineage')


def _normalize_numbers(value):
    """Return a JSON-compatible copy in which every non-boolean number is a float (1 == 1.0)."""
    if isinstance(value, dict):
        return {str(key): _normalize_numbers(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [_normalize_numbers(item) for item in value]
    if isinstance(value, bool) or value is None or isinstance(value, str):
        return value
    if isinstance(value, (int, float)):
        return float(value)
    return str(value)


def _canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False)


def make_request_spec(science, inputs, environment, runtime):
    """Return (normalized_spec, fingerprint). Read the contract before editing."""
    # runtime (output/log paths) is deliberately not used: storage location is not identity.
    settings = {key: value for key, value in science.items() if key != 'inputs'}
    spec = {
        'stage': science['stage'],
        'equivalence_policy': POLICY,
        'settings': _normalize_numbers(settings),
        'inputs': [{'role': role, **{field: inputs[role][field] for field in INPUT_FIELDS}}
                   for role in ('red', 'nir')],
        'environment': environment,
    }
    spec = json.loads(_canonical(spec))  # detached, JSON-compatible copy
    fingerprint = hashlib.sha256(_canonical(spec).encode()).hexdigest()
    return spec, fingerprint


def _finite_number(value):
    return not isinstance(value, bool) and isinstance(value, (int, float)) and math.isfinite(value)


def validate_pair(red, nir):
    """Raise ValueError if metadata cannot justify a red/NIR calculation."""
    if red['lineage'].get('asset_key') != 'red' or nir['lineage'].get('asset_key') != 'nir':
        raise ValueError('Roles must be red then nir, matching each input band')
    for key in ('collection', 'item_id', 'aoi_key', 'recipe_version'):
        if red['lineage'].get(key) is None or red['lineage'].get(key) != nir['lineage'].get(key):
            raise ValueError(f'Inputs differ in lineage: {key}')
    for key in ('crs', 'shape', 'transform'):
        if red['raster'].get(key) is None or red['raster'].get(key) != nir['raster'].get(key):
            raise ValueError(f'Input grids differ: {key}; resampling is outside this stage')
    for role, record in (('red', red), ('nir', nir)):
        meta = record['raster']
        for key in ('scale', 'offset', 'nodata'):
            if not _finite_number(meta.get(key)):
                raise ValueError(f'{role} {key} must be a finite number')
        if meta['scale'] <= 0:
            raise ValueError(f'{role} scale must be positive')


def calculate_ndvi(red, nir, red_meta, nir_meta, epsilon):
    """Return float32 NDVI; invalid pixels must be NaN. Inputs are stored DN."""
    valid = (red != red_meta['nodata']) & (nir != nir_meta['nodata'])
    # Convert to float BEFORE any arithmetic, then apply each band's own scale and offset.
    r = red.astype('float64') * red_meta['scale'] + red_meta['offset']
    n = nir.astype('float64') * nir_meta['scale'] + nir_meta['offset']
    denominator = n + r
    valid &= np.abs(denominator) > epsilon
    ndvi = np.full(red.shape, np.nan, dtype='float64')
    ndvi[valid] = (n[valid] - r[valid]) / denominator[valid]
    return ndvi.astype('float32')