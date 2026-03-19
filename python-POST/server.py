#!/usr/bin/env python3
from flask import Flask, request, jsonify
import os
from pathlib import Path

app = Flask(__name__)

HOME_DIR = Path.home()

UPLOAD_DIR = HOME_DIR / "uploads"
TEMP_DIR = UPLOAD_DIR / ".chunks"

UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
TEMP_DIR.mkdir(parents=True, exist_ok=True)

os.makedirs(UPLOAD_DIR, exist_ok=True)
os.makedirs(TEMP_DIR, exist_ok=True)


@app.route('/upload', methods=['POST'])
def upload_chunk():
    file = request.files.get('file')
    filename = request.form.get('filename')
    chunk_index = request.form.get('chunk_index')
    total_chunks = request.form.get('total_chunks')

    if not file or not filename:
        return jsonify({"error": "Missing file or filename"}), 400

    chunk_index = int(chunk_index)
    total_chunks = int(total_chunks)

    chunk_filename = f"{filename}.part{chunk_index}"
    chunk_path = os.path.join(TEMP_DIR, chunk_filename)

    file.save(chunk_path)

    # Check if all chunks are uploaded
    existing_chunks = [
        f for f in os.listdir(TEMP_DIR)
        if f.startswith(filename + ".part")
    ]

    if len(existing_chunks) == total_chunks:
        final_path = os.path.join(UPLOAD_DIR, filename)

        with open(final_path, 'wb') as outfile:
            for i in range(total_chunks):
                part_path = os.path.join(TEMP_DIR, f"{filename}.part{i}")
                with open(part_path, 'rb') as infile:
                    outfile.write(infile.read())

                os.remove(part_path)

        return jsonify({
            "message": "File reassembled successfully",
            "path": final_path
        }), 200

    return jsonify({
        "message": f"Chunk {chunk_index} uploaded"
    }), 200


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
