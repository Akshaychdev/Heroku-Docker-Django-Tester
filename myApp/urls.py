from django.urls import path
from myApp.views import index


urlpatterns = [
    path('', index, name='index')
]
