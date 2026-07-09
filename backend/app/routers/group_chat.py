# Om Sai Ram
# Group chat router — group messages and chapter highlight comments.

from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session

from ..database import get_db
from ..models import User, Group, GroupMember, Chapter, GroupMessage, ChapterHighlightComment
from ..schemas import (
    SendMessageRequest,
    GroupMessageResponse,
    PostHighlightCommentRequest,
    HighlightCommentResponse,
)
from ..middleware.auth import get_current_user

router = APIRouter()


def _verify_membership(group_id: str, user_id: str, db: Session) -> GroupMember:
    """Raise 403 if user is not a member of the group."""
    membership = (
        db.query(GroupMember)
        .filter(GroupMember.group_id == group_id, GroupMember.user_id == user_id)
        .first()
    )
    if not membership:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not a member of this group",
        )
    return membership


# ─── Group Chat ───────────────────────────────────────────────────────────────


@router.get("/{group_id}/messages", response_model=list[GroupMessageResponse])
def get_messages(
    group_id: str,
    limit: int = Query(default=50, ge=1, le=100),
    before_id: str = Query(default=None),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get recent chat messages for a group (newest-first, paginated by cursor)."""
    _verify_membership(group_id, current_user.id, db)

    query = db.query(GroupMessage).filter(GroupMessage.group_id == group_id)

    if before_id:
        anchor = db.query(GroupMessage).filter(GroupMessage.id == before_id).first()
        if anchor:
            query = query.filter(GroupMessage.created_at < anchor.created_at)

    messages = query.order_by(GroupMessage.created_at.desc()).limit(limit).all()

    result = []
    for msg in messages:
        user = db.query(User).filter(User.id == msg.user_id).first()
        result.append(
            GroupMessageResponse(
                id=msg.id,
                group_id=msg.group_id,
                user_id=msg.user_id,
                user_name=user.name if user else "Unknown",
                content=msg.content,
                created_at=msg.created_at,
            )
        )
    return result


@router.post("/{group_id}/messages", response_model=GroupMessageResponse, status_code=status.HTTP_201_CREATED)
def send_message(
    group_id: str,
    request: SendMessageRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Post a new message to the group chat."""
    _verify_membership(group_id, current_user.id, db)

    group = db.query(Group).filter(Group.id == group_id).first()
    if not group:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Group not found")

    msg = GroupMessage(
        group_id=group_id,
        user_id=current_user.id,
        content=request.content.strip(),
    )
    db.add(msg)
    db.commit()
    db.refresh(msg)

    return GroupMessageResponse(
        id=msg.id,
        group_id=msg.group_id,
        user_id=msg.user_id,
        user_name=current_user.name,
        content=msg.content,
        created_at=msg.created_at,
    )


@router.delete("/{group_id}/messages/{message_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_message(
    group_id: str,
    message_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Delete a message — only the author or a group admin/lead can do this."""
    membership = _verify_membership(group_id, current_user.id, db)

    msg = (
        db.query(GroupMessage)
        .filter(GroupMessage.id == message_id, GroupMessage.group_id == group_id)
        .first()
    )
    if not msg:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Message not found")

    is_author = msg.user_id == current_user.id
    can_moderate = membership.role in ("admin", "group_lead")

    if not is_author and not can_moderate:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You cannot delete this message",
        )

    db.delete(msg)
    db.commit()


# ─── Highlight Comments ───────────────────────────────────────────────────────


@router.get("/{group_id}/highlights", response_model=list[HighlightCommentResponse])
def get_highlight_comments(
    group_id: str,
    chapter_id: int = Query(default=None),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get all highlight comments for a group, optionally filtered by chapter."""
    _verify_membership(group_id, current_user.id, db)

    query = db.query(ChapterHighlightComment).filter(
        ChapterHighlightComment.group_id == group_id
    )
    if chapter_id is not None:
        query = query.filter(ChapterHighlightComment.chapter_id == chapter_id)

    highlights = query.order_by(ChapterHighlightComment.created_at.desc()).all()

    result = []
    for h in highlights:
        user = db.query(User).filter(User.id == h.user_id).first()
        chapter = db.query(Chapter).filter(Chapter.id == h.chapter_id).first()
        result.append(
            HighlightCommentResponse(
                id=h.id,
                group_id=h.group_id,
                user_id=h.user_id,
                user_name=user.name if user else "Unknown",
                chapter_id=h.chapter_id,
                chapter_number=chapter.number if chapter else None,
                highlighted_text=h.highlighted_text,
                paragraph_index=h.paragraph_index,
                comment=h.comment,
                created_at=h.created_at,
            )
        )
    return result


@router.post("/{group_id}/highlights", response_model=HighlightCommentResponse, status_code=status.HTTP_201_CREATED)
def post_highlight_comment(
    group_id: str,
    request: PostHighlightCommentRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Post a comment on a highlighted verse or paragraph, shared with the group."""
    _verify_membership(group_id, current_user.id, db)

    chapter = db.query(Chapter).filter(Chapter.id == request.chapter_id).first()
    if not chapter:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Chapter not found")

    highlight = ChapterHighlightComment(
        group_id=group_id,
        user_id=current_user.id,
        chapter_id=request.chapter_id,
        highlighted_text=request.highlighted_text.strip(),
        paragraph_index=request.paragraph_index,
        comment=request.comment.strip(),
    )
    db.add(highlight)
    db.commit()
    db.refresh(highlight)

    return HighlightCommentResponse(
        id=highlight.id,
        group_id=highlight.group_id,
        user_id=highlight.user_id,
        user_name=current_user.name,
        chapter_id=highlight.chapter_id,
        chapter_number=chapter.number,
        highlighted_text=highlight.highlighted_text,
        paragraph_index=highlight.paragraph_index,
        comment=highlight.comment,
        created_at=highlight.created_at,
    )


@router.delete("/{group_id}/highlights/{highlight_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_highlight_comment(
    group_id: str,
    highlight_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Delete a highlight comment — only the author or admin/lead can do this."""
    membership = _verify_membership(group_id, current_user.id, db)

    highlight = (
        db.query(ChapterHighlightComment)
        .filter(
            ChapterHighlightComment.id == highlight_id,
            ChapterHighlightComment.group_id == group_id,
        )
        .first()
    )
    if not highlight:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Comment not found")

    is_author = highlight.user_id == current_user.id
    can_moderate = membership.role in ("admin", "group_lead")

    if not is_author and not can_moderate:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You cannot delete this comment",
        )

    db.delete(highlight)
    db.commit()
