import socket
import os
import markdown
from datetime import datetime

# --- CONFIGURATION ---
BASE_ROOT = "/var/lumina"        # Root directory for all Lumina sites
HTML_MIRROR_ROOT = "/var/www/html" # Root directory for legacy web server integration
VIEW_HTML = True                 # Automatically render HTML mirrors for traditional web browsers

def start_server(host='0.0.0.0', port=1918):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    
    try:
        server.bind((host, port))
    except PermissionError:
        print("Error: Port 1918 requires higher permissions or is in use.")
        return

    server.listen(5)
    print(f"Lumina Server established at {datetime.now().strftime('%H:%M:%S')}")
    print(f"Listening on {host}:{port}...\n")
    print(f"Configuration: Root={BASE_ROOT} | HTML Mirror={VIEW_HTML}")

    while True:
        conn, addr = server.accept()
        try:
            data = conn.recv(1024).decode('utf-8').strip()
            if not data:
                conn.close()
                continue

            # Log the request
            print(f"[{datetime.now().strftime('%H:%M:%S')}] Connection from {addr[0]}")
            print(f"  Request: {data}")

            # 1. Parse Domain and Path Component Routing
            # Expecting layout: lumina://domain_or_ip/path/to/file.md
            clean_url = data.replace("lumina://", "")
            url_parts = clean_url.split("/", 1)
            
            domain = url_parts[0]
            # Default to index.md if path is empty
            req_path = url_parts[1] if len(url_parts) > 1 and url_parts[1] else "index.md"

            # 2. Strict Absolute Path Resolution (Security Jail)
            # This cleanly prevents directory traversal attacks like lumina://site/../../etc/passwd
            site_root = os.path.abspath(os.path.join(BASE_ROOT, domain))
            target_file = os.path.abspath(os.path.join(site_root, req_path))

            # Security Guard Check: Ensure the target file actually lives inside the site root directory
            if not target_file.startswith(site_root):
                conn.sendall(b"# 403 Forbidden\nAccess denied: Traversal out of protocol root detected.")
                print("  Status: 403 Forbidden (Directory Traversal Attempt)")
                continue

            # 3. Serving Logic
            if os.path.exists(target_file) and os.path.isfile(target_file):
                with open(target_file, 'rb') as f:
                    file_content = f.read()
                
                # Deliver native content directly to the Prism client
                conn.sendall(file_content)
                print(f"  Status: 200 OK ({domain}/{req_path})")

                # 4. Optional Legacy Web HTML Mirror Pipeline
                if VIEW_HTML and (target_file.endswith('.md') or target_file.endswith('.txt')):
                    try:
                        # Decode the source content safely
                        text_source = file_content.decode('utf-8')
                        
                        # Custom parsing to turn the custom link selector '=>' into working web anchors
                        lines = []
                        for line in text_source.splitlines():
                            if line.startswith("=>"):
                                parts = line[2:].strip().split(maxsplit=1)
                                url = parts[0]
                                description = parts[1] if len(parts) > 1 else parts[0]
                                # Convert .md links to .html extensions for regular web browsers
                                if url.endswith('.md'):
                                    url = url[:-3] + '.html'
                                lines.append(f'<p>📄 <a href="{url}">{description}</a></p>')
                            else:
                                lines.append(line)
                        
                        # Generate HTML content using standard layout configurations
                        html_body = markdown.markdown("\n".join(lines), extensions=['tables', 'extra'])
                        
                        full_html_document = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>{domain} - {os.path.basename(target_file)}</title>
    <style>
        body {{ font-family: -apple-system, sans-serif; line-height: 1.6; max-width: 800px; margin: 40px auto; padding: 0 20px; background: #161616; color: #D1D1D1; }}
        a {{ color: #3B82F6; text-decoration: none; }}
        a:hover {{ text-decoration: underline; }}
        pre {{ background: #222; padding: 15px; border-radius: 4px; overflow-x: auto; }}
        table {{ border-collapse: collapse; width: 100%; margin: 20px 0; }}
        th, td {{ border: 1px solid #333; padding: 8px; text-align: left; }}
        th {{ background: #222; }}
    </style>
</head>
<body>
    {html_body}
</body>
</html>"""
                        
                        # Replicate the directory tree structure inside the web target mirror location
                        mirror_dir = os.path.join(HTML_MIRROR_ROOT, domain, os.path.dirname(req_path))
                        os.makedirs(mirror_dir, exist_ok=True)
                        
                        # Re-route file tracking name target to .html equivalent
                        mirror_filename = os.path.splitext(os.path.basename(req_path))[0] + ".html"
                        mirror_filepath = os.path.join(mirror_dir, mirror_filename)
                        
                        with open(mirror_filepath, 'w', encoding='utf-8') as mf:
                            mf.write(full_html_document)
                        print(f"  Mirror: Generated legacy HTML -> {mirror_filepath}")
                        
                    except Exception as mirror_err:
                        print(f"  Mirror Warn: HTML compilation skipped ({mirror_err})")
            
            else:
                conn.sendall(b"# 404 Not Found\nThe requested scroll does not exist.")
                print(f"  Status: 404 Not Found")
                
        except Exception as e:
            print(f"  Status: Error - {e}")
        finally:
            conn.close()
            print("-" * 30)

if __name__ == "__main__":
    # Ensure system baseline layout exists before launching setup execution loops
    try:
        os.makedirs(BASE_ROOT, exist_ok=True)
    except PermissionError:
        print(f"Notice: Root creation requires administrative privileges. Be sure `{BASE_ROOT}` exists.")
    
    start_server()
