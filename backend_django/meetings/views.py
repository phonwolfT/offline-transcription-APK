from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from .models import Meeting
from .serializers import MeetingSerializer
import uuid

class MeetingViewSet(viewsets.ModelViewSet):
    queryset = Meeting.objects.all()
    serializer_class = MeetingSerializer
    # authentication_classes = [JWTAuthentication] # To be enabled in production
    # permission_classes = [IsAuthenticated]

    def create(self, request, *args, **kwargs):
        # Allow creating with a pre-existing ID from frontend, or generate one
        data = request.data.copy()
        if 'id' not in data:
            data['id'] = str(uuid.uuid4())
        serializer = self.get_serializer(data=data)
        serializer.is_valid(raise_exception=True)
        self.perform_create(serializer)
        headers = self.get_success_headers(serializer.data)
        return Response(serializer.data, status=status.HTTP_201_CREATED, headers=headers)

    @action(detail=True, methods=['post'], url_path='upload-audio')
    def upload_audio(self, request, pk=None):
        meeting = self.get_object()
        if 'audio_file' not in request.FILES:
            return Response({"error": "audio_file is required"}, status=status.HTTP_400_BAD_REQUEST)
        
        meeting.audio_file = request.FILES['audio_file']
        meeting.save()
        return Response({"status": "audio uploaded", "meeting_id": str(meeting.id)}, status=status.HTTP_200_OK)

    @action(detail=False, methods=['post'], url_path='upload-audio')
    def upload_audio_create(self, request):
        if 'audio_file' not in request.FILES:
            return Response({"error": "audio_file is required"}, status=status.HTTP_400_BAD_REQUEST)
        
        title = request.data.get('meeting_title', 'New Meeting')
        meeting_id = request.data.get('meeting_id')
        
        if meeting_id:
            meeting, created = Meeting.objects.get_or_create(id=meeting_id, defaults={'title': title})
        else:
            meeting = Meeting.objects.create(title=title)
            
        meeting.audio_file = request.FILES['audio_file']
        meeting.save()
        return Response({"status": "audio uploaded", "meeting_id": str(meeting.id)}, status=status.HTTP_200_OK)

    @action(detail=True, methods=['post'], url_path='transcription')
    def save_transcription(self, request, pk=None):
        meeting = self.get_object()
        text = request.data.get('text')
        if text is None:
            return Response({"error": "text is required"}, status=status.HTTP_400_BAD_REQUEST)
        
        meeting.transcription_text = text
        meeting.save()
        return Response({"status": "transcription saved"}, status=status.HTTP_200_OK)
