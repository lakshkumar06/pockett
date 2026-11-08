"""Small fail-closed interpreter for the bundled Agent 1 JSON schema (no dependencies)."""
import json
import re
from pathlib import Path
from urllib.parse import urlsplit


def validate_schema(value, schema, root=None):
    root = root or schema
    if '$ref' in schema:
        ref = schema['$ref']
        if not ref.startswith('#/'): raise ValueError('Unsupported schema reference')
        target = root
        for key in ref[2:].split('/'): target = target[key]
        return validate_schema(value, target, root)
    if 'oneOf' in schema:
        matches = 0
        for alternative in schema['oneOf']:
            try: validate_schema(value, alternative, root); matches += 1
            except ValueError: pass
        if matches != 1: raise ValueError('Value does not match one supported variant')
    if 'anyOf' in schema:
        for alternative in schema['anyOf']:
            try: validate_schema(value, alternative, root); break
            except ValueError: pass
        else: raise ValueError('Value does not match a supported variant')
    if 'const' in schema and (isinstance(value, bool) != isinstance(schema['const'], bool) or value != schema['const']): raise ValueError('Unsupported constant')
    if 'enum' in schema and value not in schema['enum']: raise ValueError('Unsupported value')
    kind = schema.get('type')
    types = {'object': dict, 'array': list, 'string': str, 'integer': int, 'number': (int, float), 'boolean': bool, 'null': type(None)}
    if kind and (not isinstance(value, types[kind]) or kind in ('number', 'integer') and isinstance(value, bool)):
        raise ValueError('Wrong value type')
    if isinstance(value, dict):
        if any(key not in value for key in schema.get('required', [])): raise ValueError('Missing required field')
        properties = schema.get('properties', {})
        if schema.get('additionalProperties') is False and set(value) - set(properties): raise ValueError('Unknown field')
        for key, child in value.items():
            if key in properties: validate_schema(child, properties[key], root)
    if isinstance(value, list):
        if not schema.get('minItems', 0) <= len(value) <= schema.get('maxItems', float('inf')): raise ValueError('Invalid array size')
        if schema.get('uniqueItems') and len({json.dumps(x, sort_keys=True) for x in value}) != len(value): raise ValueError('Duplicate items')
        for child in value: validate_schema(child, schema.get('items', {}), root)
    if isinstance(value, str):
        if not schema.get('minLength', 0) <= len(value) <= schema.get('maxLength', float('inf')): raise ValueError('Invalid string size')
        if 'pattern' in schema and not re.search(schema['pattern'], value): raise ValueError('Invalid string pattern')
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if not schema.get('minimum', float('-inf')) <= value <= schema.get('maximum', float('inf')): raise ValueError('Number outside bounds')


def https_url(value):
    if not isinstance(value, str) or len(value) > 2048: raise ValueError('Invalid HTTPS URL')
    try:
        url = urlsplit(value)
        if url.scheme != 'https' or not url.hostname or url.username is not None or url.password is not None or url.query or url.fragment or any(c.isspace() for c in value): raise ValueError()
        url.port
    except ValueError: raise ValueError('Use a public HTTPS URL without credentials, query or fragment')
    return value


def validate_configuration(config):
    if len(json.dumps(config, ensure_ascii=False, separators=(',', ':'), allow_nan=False).encode()) > 65536: raise ValueError('Configuration exceeds 64 KiB')
    def depth(value, level=0):
        if level > 16: raise ValueError('Configuration nesting exceeds 16')
        if isinstance(value, dict):
            for child in value.values(): depth(child, level + 1)
        elif isinstance(value, list):
            for child in value: depth(child, level + 1)
    depth(config)
    schema = json.loads((Path(__file__).parents[1] / 'Developer/Contracts/experience.schema.json').read_text())
    validate_schema(config, schema)
    if not config['metadata']['name'].strip() or not config['metadata']['summary'].strip() or any(not s['title'].strip() for s in config['screens']): raise ValueError('Empty display text')
    caps = set(config['capabilities'])
    def require(cap):
        if cap not in caps: raise ValueError('Missing declared capability: ' + cap)
    if 'liveActivity.route' in caps: require('route.recording')
    screens = [s['id'] for s in config['screens']]
    sources = config.get('dataSources', [])
    source_ids = [s['id'] for s in sources]
    if len(set(screens)) != len(screens) or len(set(source_ids)) != len(source_ids): raise ValueError('Duplicate identifiers')
    fields = {}
    for source in sources:
        https_url(source['url'])
        if any(key in ('__proto__', 'prototype', 'constructor') for f in source['response']['fields'] for key in f['path']): raise ValueError('Forbidden field path')
        names = [f['name'] for f in source['response']['fields']]
        if len(set(names)) != len(names): raise ValueError('Duplicate field names')
        fields[source['id']] = {f['name']: f['type'] for f in source['response']['fields']}
    for screen in config['screens']:
        for component in screen['components']:
            if component['type'] == 'routeMap': require('route.recording')
            binding = component.get('binding')
            if binding:
                if binding['source'] == 'route':
                    require('route.recording')
                    if binding['type'] != ('string' if binding['field'] == 'status' else 'number'): raise ValueError('Route binding type mismatch')
                elif fields.get(binding['dataSource'], {}).get(binding['field']) != binding['type']: raise ValueError('Unknown or mismatched data binding')
            action = component.get('action')
            if action:
                kind = action['type']
                if kind.startswith('route.'): require('route.recording')
                if kind.startswith('liveActivity.'): require('liveActivity.route'); require('route.recording')
                if kind == 'navigate' and action['screen'] not in screens: raise ValueError('Unknown screen')
                if kind == 'data.refresh' and action['dataSource'] not in source_ids: raise ValueError('Unknown data source')
    return config
