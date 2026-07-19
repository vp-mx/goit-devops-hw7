from django.contrib import admin
from django.urls import path

from core.views import index

urlpatterns = [
    path("admin/", admin.site.urls),
    # Health/home endpoint that also proves the DB connection works
    path("", index),
]
