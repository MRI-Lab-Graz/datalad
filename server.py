#!/usr/bin/env python3
import os
import sys

def check_venv():
    """Ensure the script runs within the local .venv virtual environment."""
    # Check if already in a virtual environment
    is_venv = hasattr(sys, 'real_prefix') or (hasattr(sys, 'base_prefix') and sys.base_prefix != sys.prefix)
    if is_venv:
        return

    # Check for .venv in the current directory
    venv_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.venv')
    python_exe = 'Scripts/python.exe' if os.name == 'nt' else 'bin/python'
    venv_python = os.path.join(venv_dir, python_exe)

    if os.path.exists(venv_python):
        print(f"🔄 Activating virtual environment: {venv_dir}")
        os.execv(venv_python, [venv_python] + sys.argv)
    else:
        print(f"⚠️ Warning: .venv not found at {venv_dir}. Running with system python.")

# Boot the venv before importing third-party modules
check_venv()

import subprocess
import json
import threading
import psutil
import socket
import webbrowser
from flask import Flask, render_template, request, jsonify
from flask_socketio import SocketIO, emit
from waitress import serve

app = Flask(__name__)
app.config['SECRET_KEY'] = 'secret!'
# Use threading mode for SocketIO as it's more standard and avoids eventlet/gevent complexity
# Waitress doesn't support WebSockets, so we will use long-polling.
socketio = SocketIO(app, cors_allowed_origins="*", async_mode='threading', logger=False, engineio_logger=False)

CONFIG_FILE = 'web_config.json'
DEFAULT_CONFIG = {
    "src_dir": "",
    "dest_root": "",
    "flags": {
        "skip_bids_validation": False,
        "dry_run": False,
        "backup": False,
        "parallel_hash": False,
        "force_empty": False,
        "fasttrack": False,
        "update": False,
        "no_gzheader_check": False
    }
}

def load_config():
    if os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, 'r') as f:
            return {**DEFAULT_CONFIG, **json.load(f)}
    return DEFAULT_CONFIG

def save_config(config):
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f, indent=4)

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/config', methods=['GET'])
def get_config():
    return jsonify(load_config())

@app.route('/api/config', methods=['POST'])
def update_config():
    config = request.json
    save_config(config)
    return jsonify({"status": "success"})

@app.route('/api/list_dirs', methods=['GET'])
def list_dirs():
    path = request.args.get('path', os.path.expanduser('~'))
    if not path: path = '/'
    try:
        # Get absolute path and ensure it's a directory
        abs_path = os.path.abspath(path)
        if not os.path.exists(abs_path):
            return jsonify({"error": "Path does not exist"}), 404
        
        parent = os.path.dirname(abs_path)
        items = []
        for item in sorted(os.listdir(abs_path)):
            full_path = os.path.join(abs_path, item)
            if os.path.isdir(full_path):
                items.append(item)
        
        return jsonify({
            "current_path": abs_path,
            "parent_path": parent,
            "directories": items
        })
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/create_dir', methods=['POST'])
def create_dir():
    data = request.json
    path = data.get('path')
    if not path:
        return jsonify({"error": "Path is required"}), 400
    
    try:
        # Handle SSH paths: user@host:/path
        if '@' in path and ':' in path:
            host_part, remote_path = path.split(':', 1)
            # Use ssh to create the directory
            res = subprocess.run(
                ["ssh", "-o", "BatchMode=yes", host_part, f"mkdir -p '{remote_path}'"],
                capture_output=True, text=True
            )
            if res.returncode != 0:
                return jsonify({"error": f"SSH Error: {res.stderr}"}), 500
            return jsonify({"status": "success", "path": path})
        else:
            # Local directory creation
            os.makedirs(path, exist_ok=True)
            return jsonify({"status": "success", "path": os.path.abspath(path)})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/preflight', methods=['GET'])
def preflight():
    checks = {
        "datalad": False,
        "git": False,
        "git_annex": False,
        "deno": False,
        "disk_space": "Unknown"
    }
    
    # Check datalad
    try:
        subprocess.run(["datalad", "--version"], capture_output=True, check=True)
        checks["datalad"] = True
    except: pass

    # Check git
    try:
        subprocess.run(["git", "--version"], capture_output=True, check=True)
        checks["git"] = True
    except: pass

    # Check git-annex
    try:
        subprocess.run(["git-annex", "version"], capture_output=True, check=True)
        checks["git_annex"] = True
    except: pass

    # Check deno
    try:
        subprocess.run(["deno", "--version"], capture_output=True, check=True)
        checks["deno"] = True
    except: pass

    # Disk space
    usage = psutil.disk_usage('/')
    checks["disk_space"] = f"{usage.free // (1024**3)} GB free"

    return jsonify(checks)

@app.route('/shutdown', methods=['POST'])
def shutdown():
    """Shutdown the Flask server when requested by the frontend."""
    print("Shutdown requested...")
    os._exit(0)
    return jsonify(success=True)

active_process = None

@socketio.on('start_process')
def handle_start_process(data):
    global active_process
    if active_process and active_process.poll() is None:
        emit('error', {'message': 'A process is already running'})
        return

    config = data.get('config', load_config())
    
    cmd = ["bash", "bids2datalad.sh"]
    cmd.extend(["-s", config['src_dir']])
    cmd.extend(["-d", config['dest_root']])
    
    flags = config.get('flags', {})
    if flags.get('skip_bids_validation'): cmd.append("--skip_bids_validation")
    if flags.get('dry_run'): cmd.append("--dry-run")
    if flags.get('backup'): cmd.append("--backup")
    if flags.get('parallel_hash'): cmd.append("--parallel-hash")
    if flags.get('force_empty'): cmd.append("--force-empty")
    if flags.get('fasttrack'): cmd.append("--fasttrack")
    if flags.get('update'): cmd.append("--update")
    if flags.get('no_gzheader_check'): cmd.append("--no-gzheader-check")
    
    def run_script():
        global active_process
        active_process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            env={**os.environ, "PYTHONUNBUFFERED": "1"}
        )
        
        for line in active_process.stdout:
            socketio.emit('terminal_output', {'data': line})
        
        active_process.wait()
        socketio.emit('process_finished', {'exit_code': active_process.returncode})

    threading.Thread(target=run_script).start()

def is_port_in_use(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        return s.connect_ex(('localhost', port)) == 0

if __name__ == '__main__':
    base_port = 8080
    max_retries = 10
    target_port = None

    for port in range(base_port, base_port + max_retries):
        if not is_port_in_use(port):
            target_port = port
            break
    
    if target_port:
        url = f"http://localhost:{target_port}"
        print(f"🚀 BIDS2DataLad Web Interface: {url}")
        # Open browser in a separate thread
        def open_browser():
            threading.Timer(1.5, lambda: webbrowser.open(url)).start()
        open_browser()
        
        # Using waitress for production-ready serving as requested
        # Note: WebSockets will fall back to long-polling via threading mode
        serve(app, host='0.0.0.0', port=target_port, _quiet=True)
    else:
        print(f"❌ Could not find an available port after {max_retries} attempts.")
