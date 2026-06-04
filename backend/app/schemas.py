from __future__ import annotations

from pydantic import BaseModel, Field


class RedeemInviteRequest(BaseModel):
    code: str = Field(min_length=16)


class RedeemInviteResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    label: str
