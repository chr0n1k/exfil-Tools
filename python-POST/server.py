#!/usr/bin/env python3
"""
python-POST Server.

Written by: Amarjit Labhuram @amarjit_labu
GIT: https://github.com/chr0n1k

This is the server side which will host a listener and collect the chunks of 
exfiltrated data into the upload folder created in the users $home directory.
"""

from flask import Flask, request, jsonify
from pathlib import Path
import os
import uuid

app = Flask(__name__)

BASE_DIR = Path.home() / "uploads"
BASE_DIR.mkdir(parents=True, exist_ok=True)


def get_upload_paths(user, upload_id):
    user_dir = BASE_DIR / user
    upload_dir = user_dir / upload_id
    chunk_dir = upload_dir / ".chunks"

    chunk_dir.mkdir(parents=True, exist_ok=True)

    return user_dir, upload_dir, chunk_dir


@app.route('/upload', methods=['POST'])
def upload_chunk():
    file = request.files.get('file')
    filename = request.form.get('filename')
    chunk_index = request.form.get('chunk_index')
    total_chunks = request.form.get('total_chunks')
    upload_id = request.form.get('upload_id')
    user = request.form.get('user')

    if not all([file, filename, chunk_index, total_chunks, upload_id, user]):
        return jsonify({"error": "Missing parameters"}), 400

    chunk_index = int(chunk_index)
    total_chunks = int(total_chunks)

    _, upload_dir, chunk_dir = get_upload_paths(user, upload_id)

    chunk_path = chunk_dir / f"chunk_{chunk_index}"
    file.save(chunk_path)

    # Check completion
    existing_chunks = list(chunk_dir.glob("chunk_*"))

    if len(existing_chunks) == total_chunks:
        final_path = upload_dir / filename

        with open(final_path, 'wb') as outfile:
            for i in range(total_chunks):
                part_path = chunk_dir / f"chunk_{i}"
                with open(part_path, 'rb') as infile:
                    outfile.write(infile.read())

        # Cleanup
        for f in chunk_dir.glob("*"):
            f.unlink()
        chunk_dir.rmdir()

        return jsonify({
            "message": "File reassembled",
            "path": str(final_path)
        }), 200

    return jsonify({
        "message": f"Chunk {chunk_index} uploaded"
    }), 200


@app.route('/status', methods=['GET'])
def upload_status():
    upload_id = request.args.get('upload_id')
    user = request.args.get('user')

    if not upload_id or not user:
        return jsonify({"error": "Missing parameters"}), 400

    _, _, chunk_dir = get_upload_paths(user, upload_id)

    if not chunk_dir.exists():
        return jsonify({"uploaded_chunks": []})

    uploaded = [
        int(p.name.split("_")[1])
        for p in chunk_dir.glob("chunk_*")
    ]

    return jsonify({"uploaded_chunks": uploaded})


if __name__ == '__main__':

    
    print("python-POST Server")
    print("Written by: Amarjit Labhuram (@amarjit_labu)")
    
    print(r"""
	   p   y   t   h   o   n   -   P   O   S   T
	  -----------------------------------------
	     ____        _   _                 
	    |  _ \ _   _| |_| |__   ___  _ __  
	    | |_) | | | | __| '_ \ / _ \| '_ \ 
	    |  __/| |_| | |_| | | | (_) | | | |
	    |_|    \__, |\__|_| |_|\___/|_| |_|
	           |___/        POST
           ╠══════════════════════════════════════╣
	   ║  Covert HTTP POST Communication      ║
	   ║  Lightweight | Stealth | Modular     ║
	   ╚══════════════════════════════════════╝
	""")
    print("python-POST module loaded")

    app.run(host='0.0.0.0', port=5000)

