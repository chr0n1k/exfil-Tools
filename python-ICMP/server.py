#!/usr/bin/env python3
import socket
import struct
import time
from pathlib import Path

# Constants
MAGIC = b'ICMP'
HEADER_SIZE = 12

class ICMPReceiver:
    def __init__(self, upload_dir=None):
        self.upload_dir = Path(upload_dir) if upload_dir else Path.home() / "uploads"
        self.upload_dir.mkdir(parents=True, exist_ok=True)

        # Active transfers
        self.transfers = {}

    def create_raw_socket(self):
        try:
            return socket.socket(socket.AF_INET, socket.SOCK_RAW, socket.IPPROTO_ICMP)
        except PermissionError:
            print("[!] Run as root (sudo required)")
            raise

    def parse_ip_header(self, data):
        ihl = data[0] & 0x0F
        return ihl * 4

    def parse_icmp_packet(self, packet):
        icmp_type = packet[0]
        icmp_code = packet[1]
        payload = packet[8:]
        return icmp_type, icmp_code, payload

    def parse_metadata(self, payload):
        if len(payload) < HEADER_SIZE:
            return None

        if payload[:4] != MAGIC:
            return None

        total_chunks = struct.unpack('!H', payload[4:6])[0]
        seq = struct.unpack('!H', payload[6:8])[0]
        chunk_size = struct.unpack('!H', payload[8:10])[0]
        filename_len = struct.unpack('!H', payload[10:12])[0]

        offset = HEADER_SIZE
        filename = None

        if seq == 0 and filename_len > 0:
            filename = payload[offset:offset + filename_len].decode(errors="ignore")
            offset += filename_len

        data = payload[offset:offset + chunk_size]

        return {
            "total_chunks": total_chunks,
            "seq": seq,
            "data": data,
            "filename": filename
        }

    def get_transfer(self, src_ip, metadata):
        """
        Use source IP as base ID, then upgrade to filename once known.
        """
        base_id = src_ip

        if base_id not in self.transfers:
            self.transfers[base_id] = {
                "total_chunks": metadata["total_chunks"],
                "filename": None,
                "chunks": {},
                "last_update": time.time()
            }

        transfer = self.transfers[base_id]

        # Capture filename from first chunk
        if metadata["seq"] == 0 and metadata["filename"]:
            transfer["filename"] = metadata["filename"]

        return base_id, transfer

    def store_chunk(self, src_ip, metadata):
        transfer_id, transfer = self.get_transfer(src_ip, metadata)

        seq = metadata["seq"]

        # Avoid duplicate overwrite spam
        if seq not in transfer["chunks"]:
            transfer["chunks"][seq] = metadata["data"]

        transfer["last_update"] = time.time()

        print(f"[+] {src_ip} -> chunk {seq}/{transfer['total_chunks']-1} "
              f"({len(transfer['chunks'])}/{transfer['total_chunks']})")

        # Check completion
        if len(transfer["chunks"]) == transfer["total_chunks"]:
            self.reassemble(transfer_id)

    def reassemble(self, transfer_id):
        transfer = self.transfers[transfer_id]

        total = transfer["total_chunks"]
        chunks = transfer["chunks"]
        filename = transfer["filename"] or f"recovered_{int(time.time())}.bin"

        expected = set(range(total))
        received = set(chunks.keys())

        if expected != received:
            missing = sorted(list(expected - received))
            print(f"[!] Missing chunks: {missing[:10]} ...")
            return

        print(f"[*] Reassembling file: {filename}")

        data = b''.join(chunks[i] for i in range(total))

        output_path = self.upload_dir / filename
        with open(output_path, "wb") as f:
            f.write(data)

        print(f"[✓] Saved: {output_path} ({len(data)} bytes)")

        # Cleanup
        del self.transfers[transfer_id]

    def cleanup(self, timeout=300):
        now = time.time()
        stale = []

        for tid, t in self.transfers.items():
            if now - t["last_update"] > timeout:
                stale.append(tid)

        for tid in stale:
            print(f"[!] Cleaning stale transfer: {tid}")
            del self.transfers[tid]

    def listen(self):
        sock = self.create_raw_socket()

        print("[*] ICMP Receiver Started")
        print(f"[*] Saving to: {self.upload_dir}")
        print("[*] Waiting for data...\n")

        try:
            while True:
                packet, addr = sock.recvfrom(65535)
                src_ip = addr[0]

                ip_len = self.parse_ip_header(packet)
                icmp_packet = packet[ip_len:]

                icmp_type, _, payload = self.parse_icmp_packet(icmp_packet)

                if icmp_type not in [0, 8]:
                    continue

                metadata = self.parse_metadata(payload)
                if not metadata:
                    continue

                self.store_chunk(src_ip, metadata)

                # Periodic cleanup
                if int(time.time()) % 30 == 0:
                    self.cleanup()

        except KeyboardInterrupt:
            print("\n[*] Stopping receiver...")
        finally:
            sock.close()


if __name__ == "__main__":
    receiver = ICMPReceiver()
    receiver.listen()
