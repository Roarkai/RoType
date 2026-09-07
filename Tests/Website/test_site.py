#!/usr/bin/env python3
"""Read-only browser QA of the website; never touches native IME/microphone/desktop targets.
Requires: python3 -m pip install playwright
Usage: python3 Tests/Website/test_site.py [http://127.0.0.1:4173]
"""
import os
from pathlib import Path
import sys
from playwright.sync_api import expect, sync_playwright

BASE = (sys.argv[1] if len(sys.argv) > 1 else 'http://127.0.0.1:4173').rstrip('/')
RELEASE = 'https://github.com/Roarkai/RoType/releases'
DOWNLOAD = RELEASE + '/download/v0.0.1/'
CHROME = os.environ.get('CHROME_PATH', '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
OUT = Path('/tmp/rotype-website-qa')
OUT.mkdir(exist_ok=True)
with sync_playwright() as p:
    browser = p.chromium.launch(executable_path=CHROME, headless=True)
    for width in [320, 390, 768, 1024, 1440]:
        for scheme in ['light', 'dark']:
            context = browser.new_context(viewport={'width': width, 'height': 900}, color_scheme=scheme)
            page = context.new_page()
            errors = []
            page.on('pageerror', lambda error: errors.append(str(error)))
            page.on('console', lambda message: errors.append(message.text) if message.type == 'error' else None)
            response = page.goto(BASE + '/', wait_until='networkidle')
            assert response.status == 200
            assert not page.evaluate('document.documentElement.scrollWidth > innerWidth'), (width, scheme)
            assert page.locator('h1').count() == 1
            assert page.locator('.hero-actions .button').bounding_box()['y'] < 900
            assert f'settings-{scheme}.webp' in page.locator('#hero-image').evaluate('(image) => image.currentSrc')
            page.locator('img').evaluate_all('(images) => images.forEach(image => image.loading = "eager")')
            for image in page.locator('img').all():
                expect(image).to_have_js_property('complete', True)
                assert image.evaluate('(node) => node.naturalWidth') > 0
            page.screenshot(path=str(OUT / f'{width}-{scheme}.png'), full_page=True)
            assert page.locator('.site-links a').count() == 2
            assert page.get_by_role('link', name='GitHub 仓库').get_attribute('href') == 'https://github.com/Roarkai/RoType'
            assert page.get_by_role('link', name='个人站点 Roarkist').get_attribute('href') == 'https://roarkist.com'
            assert page.locator('.showcase img').count() == 2
            assert page.locator('script').count() == 0
            assert page.locator('.hero h1').inner_text() == '中文输入，\n不止于打字。'
            assert page.locator('.hero .eyebrow').inner_text() == '为你的 Mac，多一种表达。'
            assert page.locator('.hero-actions .button').count() == 1
            assert page.locator('.hero-actions a').count() == 1
            assert page.locator('.hero-actions a').get_attribute('href') == DOWNLOAD + 'RoType-0.0.1-arm64.pkg'
            assert page.locator('a[href^="/downloads/"]').count() == 0
            assert page.get_by_role('link', name='SHA-256 校验', exact=True).get_attribute('href') == DOWNLOAD + 'SHA256SUMS.txt'
            assert page.get_by_role('link', name='源码', exact=True).get_attribute('href') == DOWNLOAD + 'RoType-0.0.1-source.tar.gz'
            assert page.locator('.requirements').get_attribute('open') is not None
            for selector in ['.requirements summary', '.requirements p']:
                assert int(page.locator(selector).evaluate('(node) => getComputedStyle(node).fontWeight')) >= 600
            page.locator('.requirements summary').click()
            assert page.locator('.requirements').get_attribute('open') is None
            page.locator('.requirements summary').press('Enter')
            assert page.locator('.requirements').get_attribute('open') is not None
            desired = 'dark' if scheme == 'light' else 'light'
            page.emulate_media(color_scheme=desired)
            expect(page.locator('#hero-image')).to_have_js_property('currentSrc', BASE + f'/assets/settings-{desired}.webp')
            assert not errors, errors
            context.close()
            print(f'PASS {width}px {scheme}: layout, screenshots, two icon links, system theme, details, no scripts')
    context = browser.new_context(reduced_motion='reduce')
    page = context.new_page()
    page.goto(BASE + '/', wait_until='networkidle')
    assert page.locator('.button').first.evaluate('(node) => getComputedStyle(node).transitionDuration') == '0s'
    links = page.locator('a[href^="/"]').evaluate_all('(nodes) => [...new Set(nodes.map(node => node.getAttribute("href").split("#")[0]))]')
    for link in links:
        response = context.request.head(BASE + link)
        assert response.status == 200, (link, response.status)
    for route in ['/privacy/', '/releases/']:
        page.goto(BASE + route, wait_until='networkidle')
        assert page.locator('h1').count() == 1
        assert page.locator('.site-links a').count() == 2
        assert page.locator('a[href^="/downloads/"]').count() == 0
        if route == '/releases/':
            assert page.locator('a.button').get_attribute('href') == DOWNLOAD + 'RoType-0.0.1-arm64.pkg'
            assert page.get_by_role('link', name='SHA-256 校验和').get_attribute('href') == DOWNLOAD + 'SHA256SUMS.txt'
            assert 'Build 48' not in page.locator('body').inner_text()
        assert not page.evaluate('document.documentElement.scrollWidth > innerWidth')
    context.close()
    context = browser.new_context(java_script_enabled=False, viewport={'width': 390, 'height': 844})
    page = context.new_page()
    page.goto(BASE + '/')
    assert page.locator('.requirements').get_attribute('open') is not None
    page.locator('.requirements summary').click()
    assert page.locator('.requirements').get_attribute('open') is None
    assert page.locator('.hero-actions .button').get_attribute('href').endswith('.pkg')
    context.close()
    browser.close()
print('PASS internal URLs, document pages, reduced motion and no-JS reading/download/details')
