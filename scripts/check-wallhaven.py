#!/usr/bin/env python3
"""Explicit live contract check. No credentials, writes, or downloaded originals."""
import json
import time
import urllib.error
import urllib.parse
import urllib.request


def get(path, **parameters):
    url = 'https://wallhaven.cc/api/v1/' + path
    if parameters:
        url += '?' + urllib.parse.urlencode(parameters)
    request = urllib.request.Request(url, headers={'Accept': 'application/json', 'User-Agent': 'Openpaper-contract/0.1'})
    with urllib.request.urlopen(request, timeout=30) as response:
        assert response.status == 200, response.status
        data = json.load(response)
    time.sleep(1.5)
    return data


def main():
    for order in ('date_added', 'hot', 'toplist', 'random'):
        listing = get('search', sorting=order, purity='100', categories='111')
        assert isinstance(listing['data'], list) and listing['meta']['current_page'] == 1
        assert all(w['purity'] == 'sfw' for w in listing['data'])
        if order == 'random':
            seed = listing['meta']['seed']
            assert isinstance(seed, str) and len(seed) == 6
            second = get('search', sorting=order, purity='100', categories='111', seed=seed, page=2)
            assert not {w['id'] for w in listing['data']} & {w['id'] for w in second['data']}
            if second['meta']['seed'] != seed:
                print('NOTE provider returned a different seed; Openpaper preserves the initial seed')
        print(f'PASS {order}: {len(listing["data"])} results')
    exact = get('search', purity='100', resolutions='1920x1080,2560x1440', ratios='16x9,16x10')
    assert all(w['resolution'] in ('1920x1080', '2560x1440') for w in exact['data'])
    first = exact['data'][0]
    detail = get('w/' + first['id'])['data']
    assert detail['id'] == first['id'] and isinstance(detail.get('tags'), list)
    if detail['tags']:
        tag = get('tag/' + str(detail['tags'][0]['id']))['data']
        assert tag['id'] == detail['tags'][0]['id']
    print('PASS combined resolutions/ratios, detail and tag')


if __name__ == '__main__':
    main()
