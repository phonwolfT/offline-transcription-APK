from django.db import models

class Meeting(models.Model):
    id = models.CharField(max_length=255, primary_key=True)
    title = models.CharField(max_length=255)
    language = models.CharField(max_length=50)
    source = models.CharField(max_length=50)
    duration_seconds = models.IntegerField(default=0)
    audio_file = models.FileField(upload_to='meetings/audio/', null=True, blank=True)
    transcription_text = models.TextField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.title
