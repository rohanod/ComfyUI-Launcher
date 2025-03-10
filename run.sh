#!/bin/bash
echo "Installing required packages..."
echo
pip install -r requirements.txt

echo
echo
echo "ComfyUI Launcher is starting..."
echo
echo

cd server/

# start Celery worker in the bg
celery -A server.celery_app --workdir=. worker --loglevel=DEBUG &
celery_worker_pid=$!
echo "Celery worker started with PID: $celery_worker_pid"

# Install cloudflared
echo "Installing cloudflared..."
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
dpkg -i cloudflared-linux-amd64.deb

# Find an open port
find_open_port() {
  local port=8188
  while netstat -tulnp | grep -q ":$port "; do
    port=$((port + 1))
  done
  echo $port
}

PORT=$(find_open_port)

# Run server.py in the background and redirect output to a file
python server.py --port $PORT > server.log 2>&1 &
server_pid=$!
echo "ComfyUI server started with PID: $server_pid on port $PORT"

# Function to check if ComfyUI is running
is_comfyui_running() {
  timeout 10 bash -c "until nc -z localhost $PORT; do sleep 0.1; done"
}

# Wait for ComfyUI to start
echo "Waiting for ComfyUI to start..."
if is_comfyui_running; then
  echo "ComfyUI is running, launching cloudflared..."
  cloudflared tunnel --url http://127.0.0.1:$PORT &
  cloudflared_pid=$!
  echo "Cloudflared tunnel started with PID: $cloudflared_pid"

  # Get the cloudflared URL from the logs
  sleep 5 # Give cloudflared some time to start
  CLOUDFLARED_URL=$(grep "trycloudflare.com" server.log | tail -n 1 | awk '{print $6}')

  if [ -n "$CLOUDFLARED_URL" ]; then
    echo "ComfyUI is accessible via: $CLOUDFLARED_URL"
  else
    echo "Failed to retrieve Cloudflared URL. Check server.log for errors."
  fi
else
  echo "ComfyUI failed to start."
fi

# kill Celery worker when server.py is done
kill $celery_worker_pid
kill $server_pid
if [ -n "$cloudflared_pid" ]; then
  kill $cloudflared_pid
fi
