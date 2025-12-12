from fastapi import FastAPI, UploadFile, File, Depends, HTTPException, Form
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
from typing import Optional
import uuid
from datetime import datetime
import io
from PIL import Image

from app.schemas import (
    TextAnalysisRequest, UrlAnalysisRequest, AllAnalysisRequest,
    ChatRequest, AnalysisResponse, ChatResponse, ChatHistoryResponse,
    HealthResponse
)
from app.db.database import init_db, get_db
from app.db.repository import Repository
from app.graph.workflow import MultiAgentWorkflow

# Initialize FastAPI app
app = FastAPI(
    title="Yaqith Multi-Agent Safety System",
    description="Multi-agent system for analyzing message safety using logo, text, and URL detection",
    version="1.0.0"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global workflow instance
workflow: Optional[MultiAgentWorkflow] = None

@app.on_event("startup")
async def startup_event():
    """Initialize database and models on startup"""
    global workflow
    
    print("🚀 Initializing Yaqith Multi-Agent System...")
    
    # Initialize database
    print("📊 Initializing database...")
    try:
        init_db()
        print("✅ Database initialized")
    except Exception as e:
        print(f"❌ Database initialization failed: {e}")
        raise
    
    # Initialize workflow and load models
    print("🤖 Loading AI models...")
    print("⏳ This may take a few minutes on first run...")
    try:
        workflow = MultiAgentWorkflow()
        print("✅ All models loaded successfully")
    except Exception as e:
        print(f"❌ Model loading failed: {e}")
        print("💡 Try running 'python test_models.py' to diagnose the issue")
        raise
    
    print("🎉 System ready!")
    print("📡 API docs available at: http://localhost:8000/docs")

@app.get("/", tags=["Health"])
async def root():
    """Root endpoint"""
    return {
        "message": "Yaqith Multi-Agent Safety System",
        "status": "operational",
        "version": "1.0.0"
    }

@app.get("/health", response_model=HealthResponse, tags=["Health"])
async def health_check(db: Session = Depends(get_db)):
    """Health check endpoint"""
    models_loaded = {
        "logo_agent": hasattr(workflow.logo_agent, 'model') and workflow.logo_agent.model is not None,
        "text_agent": hasattr(workflow.text_agent, 'model') and workflow.text_agent.model is not None,
        "url_agent": hasattr(workflow.url_agent, 'model') and workflow.url_agent.model is not None
    }
    
    db_connected = True
    try:
        db.execute("SELECT 1")
    except:
        db_connected = False
    
    # Determine status
    if all(models_loaded.values()) and db_connected:
        status = "healthy"
    elif db_connected:
        status = "degraded_fallback"  # Using fallback models
    else:
        status = "degraded"
    
    return HealthResponse(
        status=status,
        models_loaded=models_loaded,
        database_connected=db_connected
    )

@app.post("/analyze/text", response_model=AnalysisResponse, tags=["Analysis"])
async def analyze_text(
    request: TextAnalysisRequest,
    db: Session = Depends(get_db)
):
    """Analyze text message for fraud/phishing"""
    try:
        repo = Repository(db)
        repo.create_or_update_session(request.session_id)
        
        # Run analysis
        result = workflow.analyze_sync(
            text=request.text,
            session_id=request.session_id
        )
        
        # Save to database
        if result.get("text_result"):
            repo.save_text_scan(
                request.session_id,
                request.text,
                result["text_result"]
            )
            
            if result["text_result"].get("is_fraud"):
                repo.save_phishing_attempt(
                    request.session_id,
                    "text",
                    request.text,
                    result["text_result"].get("reason", "Fraudulent text detected"),
                    result["text_result"].get("confidence", 0.0)
                )
        
        return AnalysisResponse(
            text_result=result.get("text_result"),
            final_decision=result.get("final_decision", "unknown"),
            risk_score=result.get("risk_score", 0.0),
            explanation=result.get("explanation", ""),
            session_id=request.session_id
        )
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/analyze/logo", response_model=AnalysisResponse, tags=["Analysis"])
async def analyze_logo(
    file: UploadFile = File(...),
    session_id: str = Form(default="default"),
    db: Session = Depends(get_db)
):
    """Analyze logo image for legitimacy"""
    try:
        repo = Repository(db)
        repo.create_or_update_session(session_id)
        
        # Read image
        contents = await file.read()
        image = Image.open(io.BytesIO(contents))
        
        # Run analysis
        result = workflow.analyze_sync(
            image=image,
            session_id=session_id
        )
        
        # Save to database
        if result.get("logo_result"):
            repo.save_logo_scan(
                session_id,
                file.filename,
                result["logo_result"]
            )
            
            if result["logo_result"].get("is_suspicious"):
                repo.save_phishing_attempt(
                    session_id,
                    "logo",
                    file.filename,
                    result["logo_result"].get("reason", "Suspicious logo detected"),
                    result["logo_result"].get("confidence", 0.0)
                )
        
        return AnalysisResponse(
            logo_result=result.get("logo_result"),
            final_decision=result.get("final_decision", "unknown"),
            risk_score=result.get("risk_score", 0.0),
            explanation=result.get("explanation", ""),
            session_id=session_id
        )
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/analyze/url", response_model=AnalysisResponse, tags=["Analysis"])
async def analyze_url(
    request: UrlAnalysisRequest,
    db: Session = Depends(get_db)
):
    """Analyze URL for safety"""
    try:
        repo = Repository(db)
        repo.create_or_update_session(request.session_id)
        
        # Run analysis
        result = workflow.analyze_sync(
            url=request.url,
            session_id=request.session_id
        )
        
        # Save to database
        if result.get("url_result"):
            repo.save_url_scan(
                request.session_id,
                request.url,
                result["url_result"]
            )
            
            if not result["url_result"].get("safe"):
                repo.save_phishing_attempt(
                    request.session_id,
                    "url",
                    request.url,
                    result["url_result"].get("reason", "Malicious URL detected"),
                    result["url_result"].get("confidence", 0.0)
                )
        
        return AnalysisResponse(
            url_result=result.get("url_result"),
            final_decision=result.get("final_decision", "unknown"),
            risk_score=result.get("risk_score", 0.0),
            explanation=result.get("explanation", ""),
            session_id=request.session_id
        )
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/analyze/all", response_model=AnalysisResponse, tags=["Analysis"])
async def analyze_all(
    text: Optional[str] = Form(None),
    url: Optional[str] = Form(None),
    file: Optional[UploadFile] = File(None),
    session_id: str = Form(default="default"),
    db: Session = Depends(get_db)
):
    """Analyze all inputs (text, URL, and/or image)"""
    try:
        repo = Repository(db)
        repo.create_or_update_session(session_id)
        
        # Prepare inputs
        image = None
        if file:
            contents = await file.read()
            image = Image.open(io.BytesIO(contents))
        
        # Run analysis
        result = workflow.analyze_sync(
            text=text,
            url=url,
            image=image,
            session_id=session_id
        )
        
        # Save results to database
        if result.get("logo_result") and file:
            repo.save_logo_scan(session_id, file.filename, result["logo_result"])
        
        if result.get("text_result") and text:
            repo.save_text_scan(session_id, text, result["text_result"])
        
        if result.get("url_result") and url:
            repo.save_url_scan(session_id, url, result["url_result"])
        
        # Save phishing attempts
        if result.get("final_decision") in ["suspicious", "dangerous"]:
            content = f"Text: {text}, URL: {url}, Image: {file.filename if file else 'None'}"
            repo.save_phishing_attempt(
                session_id,
                "combined",
                content,
                result.get("explanation", "Multiple indicators detected"),
                result.get("risk_score", 0.0)
            )
        
        return AnalysisResponse(
            logo_result=result.get("logo_result"),
            text_result=result.get("text_result"),
            url_result=result.get("url_result"),
            final_decision=result.get("final_decision", "unknown"),
            risk_score=result.get("risk_score", 0.0),
            explanation=result.get("explanation", ""),
            session_id=session_id
        )
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/chat", response_model=ChatResponse, tags=["Chat"])
async def chat(
    message: str = Form(...),
    url: Optional[str] = Form(None),
    file: Optional[UploadFile] = File(None),
    session_id: str = Form(default="default"),
    db: Session = Depends(get_db)
):
    """
    Conversational chatbot endpoint
    Analyzes message + optional URL + optional image and provides conversational response
    """
    try:
        repo = Repository(db)
        repo.create_or_update_session(session_id)
        
        # Prepare inputs
        image = None
        if file:
            contents = await file.read()
            image = Image.open(io.BytesIO(contents))
        
        # Run analysis
        result = workflow.analyze_sync(
            text=message,
            url=url,
            image=image,
            session_id=session_id
        )
        
        # Generate conversational response
        decision = result.get("final_decision", "unknown")
        risk_score = result.get("risk_score", 0.0)
        explanation = result.get("explanation", "")
        
        if decision == "safe":
            bot_message = f"✅ Everything looks good! Your message appears to be safe.\n\n{explanation}"
        elif decision == "suspicious":
            bot_message = f"⚠️ I've detected some concerning indicators. Please be cautious.\n\n{explanation}"
        else:  # dangerous
            bot_message = f"🚨 Warning! This appears to be a phishing or fraud attempt. Do not proceed!\n\n{explanation}"
        
        bot_message += f"\n\nRisk Score: {risk_score:.0%}"
        
        # Save chat history
        repo.save_message(session_id, message, bot_message)
        
        # Save analysis results
        if result.get("logo_result") and file:
            repo.save_logo_scan(session_id, file.filename, result["logo_result"])
        
        if result.get("text_result"):
            repo.save_text_scan(session_id, message, result["text_result"])
        
        if result.get("url_result") and url:
            repo.save_url_scan(session_id, url, result["url_result"])
        
        return ChatResponse(
            message=bot_message,
            analysis=AnalysisResponse(
                logo_result=result.get("logo_result"),
                text_result=result.get("text_result"),
                url_result=result.get("url_result"),
                final_decision=decision,
                risk_score=risk_score,
                explanation=explanation,
                session_id=session_id
            ),
            session_id=session_id
        )
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/chat/history", response_model=ChatHistoryResponse, tags=["Chat"])
async def get_chat_history(
    session_id: Optional[str] = None,
    limit: int = 50,
    db: Session = Depends(get_db)
):
    """Get chat history"""
    try:
        repo = Repository(db)
        history = repo.get_chat_history(session_id, limit)
        
        return ChatHistoryResponse(
            history=[
                {
                    "id": item.id,
                    "user_message": item.user_message,
                    "bot_response": item.bot_response,
                    "created_at": item.created_at
                }
                for item in history
            ],
            total=len(history)
        )
    
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)