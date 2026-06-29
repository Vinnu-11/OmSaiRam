# Om Sai Ram
# Progress router — update and query reading progress.

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import User, ReadingAssignment, ReadingProgress
from ..schemas import UpdateProgressRequest, ProgressResponse
from ..middleware.auth import get_current_user

router = APIRouter()


@router.patch("/{assignment_id}", response_model=ProgressResponse)
def update_progress(
    assignment_id: str,
    request: UpdateProgressRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Update reading progress for an assignment.

    Only the assigned user can update their own progress.
    Valid statuses: not_started, in_progress, completed.
    """
    # Get the assignment
    assignment = (
        db.query(ReadingAssignment)
        .filter(ReadingAssignment.id == assignment_id)
        .first()
    )
    if not assignment:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Assignment not found",
        )

    # Verify the current user owns this assignment
    if assignment.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You can only update your own reading progress",
        )

    # Get or create progress record
    progress = assignment.progress
    if not progress:
        progress = ReadingProgress(
            assignment_id=assignment_id,
            status=request.status,
        )
        db.add(progress)
    else:
        progress.status = request.status

    db.commit()
    db.refresh(progress)

    return ProgressResponse(
        id=progress.id,
        assignment_id=progress.assignment_id,
        status=progress.status,
        updated_at=progress.updated_at,
    )


@router.get("/{assignment_id}", response_model=ProgressResponse)
def get_progress(
    assignment_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get reading progress for a specific assignment."""
    assignment = (
        db.query(ReadingAssignment)
        .filter(ReadingAssignment.id == assignment_id)
        .first()
    )
    if not assignment:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Assignment not found",
        )

    progress = assignment.progress
    if not progress:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No progress record found",
        )

    return ProgressResponse(
        id=progress.id,
        assignment_id=progress.assignment_id,
        status=progress.status,
        updated_at=progress.updated_at,
    )
