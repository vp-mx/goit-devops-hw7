from django.db import connection
from django.http import JsonResponse


def index(request):
    """Simple endpoint proving the app is up and the DB connection works."""
    with connection.cursor() as cursor:
        cursor.execute("SELECT 1")
        cursor.fetchone()

    return JsonResponse(
        {
            "status": "ok",
            "message": "Django + PostgreSQL + Nginx are working",
        }
    )
