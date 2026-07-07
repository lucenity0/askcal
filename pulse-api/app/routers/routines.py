import uuid

from fastapi import APIRouter, Response
from sqlalchemy import select

from app.core.errors import PulseError
from app.deps import CurrentUser, DbSession
from app.models import Routine
from app.schemas.routines import RoutineCreateRequest, RoutineOut, RoutinesResponse

router = APIRouter(prefix="/api", tags=["routines"])


@router.get("/routines", response_model=RoutinesResponse)
async def list_routines(user: CurrentUser, db: DbSession) -> RoutinesResponse:
    """User-created routines, oldest first. Fresh accounts have none —
    routines are never seeded."""
    routines = (
        await db.scalars(
            select(Routine)
            .where(Routine.user_id == user.id)
            .order_by(Routine.created_at)
        )
    ).all()
    return RoutinesResponse(
        routines=[RoutineOut.model_validate(r) for r in routines]
    )


@router.post("/routines", response_model=RoutineOut, status_code=201)
async def create_routine(
    body: RoutineCreateRequest, user: CurrentUser, db: DbSession
) -> RoutineOut:
    title = body.title.strip()
    if not title:
        raise PulseError(422, "INVALID_ROUTINE", "Title is empty")
    routine = Routine(user_id=user.id, title=title, cadence=body.cadence)
    db.add(routine)
    await db.commit()
    return RoutineOut.model_validate(routine)


@router.delete("/routines/{routine_id}", status_code=204)
async def delete_routine(
    routine_id: uuid.UUID, user: CurrentUser, db: DbSession
) -> Response:
    routine = await db.scalar(
        select(Routine).where(Routine.user_id == user.id, Routine.id == routine_id)
    )
    if routine is None:
        raise PulseError(404, "NOT_FOUND", "No such routine")
    await db.delete(routine)
    await db.commit()
    return Response(status_code=204)
