#!/bin/zsh
# Explicit, synthetic-only integration test. No microphone, input client or clipboard.
set -euo pipefail
[[ $# -eq 2 ]] || { print -u2 'usage: test-voice-recognition.sh signed-worker model-directory'; exit 2; }
worker=${1:A}
model=${2:A}
[[ -x "$worker" && -d "$model" ]]
codesign --verify --strict -R '=anchor apple generic and certificate leaf[subject.OU] = "DF7J2VBQD8" and identifier "im.roarkai.inputmethod.Luoke.asr"' "$worker"
fixture=$(mktemp -d)
trap 'rm -R "$fixture"' EXIT
say -v Tingting -o "$fixture/one.aiff" '明天下午三点，在企业微信开会。预算是一千五百八十元。'
say -v Tingting -o "$fixture/two.aiff" '今天是星期三，我要买两个苹果。'
say -v Tingting -o "$fixture/three.aiff" '请把会议改到明天上午九点。'
for name in one two three; do
  afconvert -f caff -d LEI16@16000 -c 1 "$fixture/$name.aiff" "$fixture/$name.caf"
done
python3 - "$worker" "$model" "$fixture" <<'PY'
import json, os, pathlib, select, subprocess, sys, time, uuid
worker, model, fixture = sys.argv[1:]
process = subprocess.Popen([worker, model], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, bufsize=0)
buffer = bytearray()
def reply(timeout):
    deadline = time.monotonic() + timeout
    while True:
        while b'\n' in buffer:
            line, _, remaining = buffer.partition(b'\n')
            buffer[:] = remaining
            if line.startswith(b'ROTYPE_VOICE:'):
                return json.loads(line[len(b'ROTYPE_VOICE:'):])
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([process.stdout], [], [], remaining)[0]:
            raise TimeoutError('worker reply timed out')
        chunk = os.read(process.stdout.fileno(), 65536)
        if not chunk:
            raise RuntimeError('worker exited before replying')
        buffer.extend(chunk)
try:
    assert reply(90)['event'] == 'ready'
    fixtures = [('one', '企业微信'), ('two', '苹果'), ('three', '会议')]
    for index in range(18):
        name, expected = fixtures[index % len(fixtures)]
        identifier = str(uuid.uuid4())
        request = {'id': identifier, 'audioPath': str(pathlib.Path(fixture) / (name + '.caf'))}
        process.stdin.write(json.dumps(request).encode() + b'\n')
        response = reply(45)
        assert response.get('id', '').lower() == identifier, response
        assert response.get('event') == 'result' and expected in response.get('text', ''), response
        print(f'PASS {index + 1}/18: matching request ID and distinct synthetic CAF recognition', flush=True)
finally:
    process.stdin.close()
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
PY
