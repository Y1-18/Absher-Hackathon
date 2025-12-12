#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
PROJECT_DIR=$(pwd)
BACKEND_PORT=8000
FRONTEND_PORT=8080
LOG_DIR="$PROJECT_DIR/logs"

# Create logs directory
mkdir -p "$LOG_DIR"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}🚀 Yaqith - Multi-Agent Safety System${NC}"
echo -e "${MAGENTA}🛡️ Advanced Fraud & Phishing Detection${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

# Function to print status
print_status() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
    fi
}

# Function to kill previous processes
cleanup() {
    echo -e "${YELLOW}Cleaning up old processes...${NC}"
    
    # Kill old Backend
    OLD_BACKEND=$(lsof -ti:$BACKEND_PORT 2>/dev/null)
    if [ ! -z "$OLD_BACKEND" ]; then
        kill -9 $OLD_BACKEND 2>/dev/null
        print_status 0 "Killed old Backend (PID: $OLD_BACKEND)"
    fi
    
    # Kill old Frontend
    OLD_FRONTEND=$(lsof -ti:$FRONTEND_PORT 2>/dev/null)
    if [ ! -z "$OLD_FRONTEND" ]; then
        kill -9 $OLD_FRONTEND 2>/dev/null
        print_status 0 "Killed old Frontend (PID: $OLD_FRONTEND)"
    fi
    
    # Remove old PID file
    [ -f "$PROJECT_DIR/.pids" ] && rm "$PROJECT_DIR/.pids"
    
    echo ""
}

# Navigate to project
echo -e "${BLUE}Step 1: Verify Project Directory${NC}"
cd "$PROJECT_DIR" || { echo -e "${RED}❌ Cannot change to project directory${NC}"; exit 1; }
print_status 0 "In project directory: $(pwd)"
echo ""

# Check required files
echo -e "${BLUE}Step 2: Check Required Files${NC}"
required_files=("app/main.py" "app/db/database.py" "app/graph/workflow.py")
for file in "${required_files[@]}"; do
    if [ -f "$file" ]; then
        print_status 0 "$file found"
    else
        print_status 1 "$file NOT found"
    fi
done
echo ""

# Check Python and packages
echo -e "${BLUE}Step 3: Check Dependencies${NC}"
python3 --version
echo -e "${CYAN}Checking Python packages...${NC}"
python3 -c "import fastapi; print('  ✓ FastAPI: OK')" 2>/dev/null || echo -e "  ${RED}✗ FastAPI: MISSING${NC}"
python3 -c "import sqlalchemy; print('  ✓ SQLAlchemy: OK')" 2>/dev/null || echo -e "  ${RED}✗ SQLAlchemy: MISSING${NC}"
python3 -c "import PIL; print('  ✓ Pillow: OK')" 2>/dev/null || echo -e "  ${RED}✗ Pillow: MISSING${NC}"
python3 -c "import torch; print('  ✓ PyTorch: OK')" 2>/dev/null || echo -e "  ${RED}✗ PyTorch: MISSING${NC}"
echo ""

# Check GPU availability
echo -e "${BLUE}Step 4: Check GPU/Hardware${NC}"
if python3 -c "import torch; exit(0 if torch.cuda.is_available() else 1)" 2>/dev/null; then
    GPU_NAME=$(python3 -c "import torch; print(torch.cuda.get_device_name(0))" 2>/dev/null)
    print_status 0 "GPU available: $GPU_NAME"
    GPU_MEM=$(python3 -c "import torch; print(f'{torch.cuda.get_device_properties(0).total_memory / 1024**3:.1f} GB')" 2>/dev/null)
    echo -e "  ${CYAN}GPU Memory: $GPU_MEM${NC}"
else
    print_status 1 "GPU not available (will use CPU - slower)"
    echo -e "  ${YELLOW}⚠${NC}  Models will run on CPU. Expect slower inference."
fi
echo ""

# Check RAM
echo -e "${BLUE}Step 5: Check System Resources${NC}"
TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
echo -e "  ${CYAN}Total RAM: ${TOTAL_RAM}GB${NC}"
if [ "$TOTAL_RAM" -lt 8 ]; then
    echo -e "  ${YELLOW}⚠${NC}  Low RAM detected. Ensure sufficient memory available."
else
    print_status 0 "Sufficient RAM available"
fi
echo ""

# Database setup
echo -e "${BLUE}Step 6: Initialize Database${NC}"
python3 << 'EOF'
try:
    from app.db.database import init_db
    init_db()
    print("  ✓ Database initialized successfully")
except Exception as e:
    print(f"  ✗ Database initialization error: {e}")
EOF
echo ""

# Cleanup old processes
cleanup

# Start Backend (Yaqith API)
echo -e "${BLUE}Step 7: Start Backend (Yaqith API)${NC}"
echo -e "${YELLOW}Note: First startup may take time to load AI models...${NC}"
nohup python3 -m uvicorn app.main:app --host 0.0.0.0 --port $BACKEND_PORT > "$LOG_DIR/backend.log" 2>&1 &
BACKEND_PID=$!
print_status 0 "Backend started (PID: $BACKEND_PID)"

# Wait for Backend to be ready
echo -e "${YELLOW}Waiting for Backend to start (loading models)...${NC}"
TIMEOUT=300  # 5 minutes for model loading
for i in $(seq 1 $TIMEOUT); do
    if curl -s http://localhost:$BACKEND_PORT/health > /dev/null 2>&1; then
        print_status 0 "Backend is responding"
        break
    fi
    if [ $i -eq $TIMEOUT ]; then
        print_status 1 "Backend failed to start (timeout after ${TIMEOUT}s)"
        echo -e "${CYAN}Check logs: tail -50 $LOG_DIR/backend.log${NC}"
    fi
    # Show progress indicator
    if [ $((i % 10)) -eq 0 ]; then
        echo -ne "${CYAN}[$i/${TIMEOUT}s]${NC} "
    fi
    echo -n "."
    sleep 1
done
echo ""
echo ""

# Check backend health
if curl -s http://localhost:$BACKEND_PORT/health > /dev/null 2>&1; then
    echo -e "${BLUE}Backend Status:${NC}"
    curl -s http://localhost:$BACKEND_PORT/health | python3 -m json.tool 2>/dev/null | sed 's/^/  /' || echo "  ✓ Backend is healthy"
    echo ""
else
    echo -e "${RED}❌ Backend health check failed${NC}"
    echo -e "${CYAN}Last 20 lines of log:${NC}"
    tail -20 "$LOG_DIR/backend.log"
    echo ""
fi

# Start Frontend
echo -e "${BLUE}Step 8: Start Frontend Server${NC}"
nohup python3 << 'FRONTEND_EOF' > "$LOG_DIR/frontend.log" 2>&1 &
from fastapi import FastAPI
from fastapi.responses import HTMLResponse
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

app = FastAPI(title="Yaqith Frontend", version="1.0.0")

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Read HTML file
with open('frontend.html', 'r', encoding='utf-8') as f:
    html_content = f.read()

@app.get("/", response_class=HTMLResponse)
async def serve_frontend():
    return html_content

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "yaqith-frontend"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080, log_level="info")
FRONTEND_EOF

FRONTEND_PID=$!
print_status 0 "Frontend started (PID: $FRONTEND_PID)"

# Wait for Frontend
echo -e "${YELLOW}Waiting for Frontend to start...${NC}"
for i in {1..30}; do
    if curl -s http://localhost:$FRONTEND_PORT > /dev/null 2>&1; then
        print_status 0 "Frontend is responding"
        break
    fi
    if [ $i -eq 30 ]; then
        print_status 1 "Frontend failed to start"
        echo -e "${CYAN}Check logs: tail -20 $LOG_DIR/frontend.log${NC}"
    fi
    echo -n "."
    sleep 1
done
echo ""
echo ""

# Save PIDs
echo "$BACKEND_PID $FRONTEND_PID" > "$PROJECT_DIR/.pids"

# Final status
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ ALL SERVICES STARTED!${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

echo -e "${BLUE}🔗 Access Points:${NC}"
echo -e "  ${CYAN}Frontend:${NC}       http://localhost:$FRONTEND_PORT"
echo -e "  ${CYAN}Backend API:${NC}    http://localhost:$BACKEND_PORT"
echo -e "  ${CYAN}API Docs:${NC}       http://localhost:$BACKEND_PORT/docs"
echo -e "  ${CYAN}Health Check:${NC}   http://localhost:$BACKEND_PORT/health"
echo ""

echo -e "${BLUE}📊 Processes:${NC}"
echo -e "  ${CYAN}Backend (PID: $BACKEND_PID)${NC}  - Yaqith Multi-Agent System"
echo -e "  ${CYAN}Frontend (PID: $FRONTEND_PID)${NC} - Web Interface"
echo ""

echo -e "${BLUE}🤖 AI Agents:${NC}"
echo -e "  ${MAGENTA}Text Agent:${NC}      Fraud & Phishing Detection"
echo -e "  ${MAGENTA}URL Agent:${NC}       Malicious Link Analysis"
echo -e "  ${MAGENTA}Logo Agent:${NC}      Brand Authentication"
echo ""

echo -e "${BLUE}📝 Logs:${NC}"
echo -e "  ${CYAN}Backend:${NC}   tail -f $LOG_DIR/backend.log"
echo -e "  ${CYAN}Frontend:${NC}   tail -f $LOG_DIR/frontend.log"
echo ""

echo -e "${BLUE}🛑 Stop Services:${NC}"
echo -e "  ${CYAN}bash stop.sh${NC}"
echo -e "  ${CYAN}or: kill $BACKEND_PID $FRONTEND_PID${NC}\n"

echo -e "${BLUE}💡 Useful Commands:${NC}"
echo -e "  ${CYAN}Check backend:${NC}   curl http://localhost:$BACKEND_PORT/health | python3 -m json.tool"
echo -e "  ${CYAN}Monitor logs:${NC}    tail -f $LOG_DIR/backend.log"
echo -e "  ${CYAN}Monitor GPU:${NC}     watch -n 1 nvidia-smi"
echo ""

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"