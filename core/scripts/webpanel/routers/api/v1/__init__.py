from fastapi import APIRouter
from . import user
from . import server

api_v1_router = APIRouter()

api_v1_router.include_router(user.router, prefix='/users')
api_v1_router.include_router(server.router, prefix='/server')
