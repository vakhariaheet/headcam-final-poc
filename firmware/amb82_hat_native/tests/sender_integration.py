"""Run against the isolated MediaMTX container 'hat-rtmp-test' on 19350/18554.
Usage: python3 sender_integration.py /tmp/hat-sender-harness /tmp/hat-rtmp-test.h264
"""
import queue
import os
import socket
import subprocess
import sys
import threading
import time

process = subprocess.Popen(sys.argv[1:3], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True, bufsize=1,
                           env={**os.environ, "UBSAN_OPTIONS": "halt_on_error=1"})
lines = queue.Queue()

def read_output():
    for line in process.stdout:
        lines.put(line.strip())

threading.Thread(target=read_output, daemon=True).start()

def wait_for(expected, timeout=12):
    end = time.monotonic() + timeout
    seen = []
    while time.monotonic() < end:
        try:
            line = lines.get(timeout=max(0.01, end-time.monotonic()))
        except queue.Empty:
            break
        seen.append(line)
        assert "runtime error:" not in line and "ERROR: AddressSanitizer" not in line, line
        if expected in line:
            print(line, flush=True)
            return
    raise AssertionError(f"Missing {expected}; output: {seen}")

def command(value):
    process.stdin.write(value + '\n')
    process.stdin.flush()

def status(value, timeout=12):
    wait_for(f'"status":"{value}"', timeout)

def decode_video():
    # MediaMTX briefly gathers track information after publish acceptance.
    deadline = time.monotonic() + 10
    while True:
        decoded = subprocess.run(['ffmpeg', '-hide_banner', '-rtsp_transport', 'tcp',
            '-i', 'rtsp://127.0.0.1:18554/live/sender-test', '-t', '5', '-an', '-f', 'null', '-'],
            capture_output=True, text=True, timeout=20)
        if decoded.returncode == 0:
            break
        assert '404' in decoded.stderr and time.monotonic() < deadline, decoded.stderr
        time.sleep(0.3)
    assert '1920x1080' in decoded.stderr
    print('Decoded 1080p video from the real sender state machine', flush=True)

url = 'rtmp://127.0.0.1:19350/live/sender-test'
try:
    wait_for('READY')
    command('start rtmps://unsupported/live/key'); wait_for('ACCEPTED 0')
    # Exercise cancellation while a TCP peer accepts but never completes RTMP.
    with socket.socket() as stalled:
        stalled.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        stalled.bind(('127.0.0.1', 19351)); stalled.listen(); stalled.settimeout(5)
        command('start rtmp://127.0.0.1:19351/live/timeout'); wait_for('ACCEPTED 1')
        peer, _ = stalled.accept()
        with peer:
            time.sleep(0.2)
            began = time.monotonic(); command('stop'); status('stopped', 2)
            assert time.monotonic() - began < 2
    # Unavailable ingest retries; STOP must cancel backoff.
    command('start rtmp://127.0.0.1:19351/live/unavailable'); wait_for('ACCEPTED 1')
    status('reconnecting'); command('stop'); status('stopped', 2)
    command('start ' + url); wait_for('ACCEPTED 1'); status('publishing')
    command('start ' + url); wait_for('ACCEPTED 0')
    decode_video()
    subprocess.run(['docker','restart','-t','1','hat-rtmp-test'],check=True,capture_output=True)
    status('reconnecting'); status('publishing',20)
    decode_video()
    command('stop'); status('stopped',2)
    time.sleep(1)
    # No reconnect attempts after STOP.
    while not lines.empty():
        line=lines.get_nowait()
        assert '"status":"connecting"' not in line, line
    command('start ' + url); wait_for('ACCEPTED 1'); status('publishing')
    command('stop'); status('stopped',2)
    print('Sender start/stop, cancellation, duplicate-start, retry and recovery tests passed',flush=True)
finally:
    if process.poll() is None:
        command('quit')
        assert process.wait(timeout=5) == 0
