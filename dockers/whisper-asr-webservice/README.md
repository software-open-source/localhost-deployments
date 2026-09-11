# Whisper ASR Webservice
> [whisper-asr-webservice](https://github.com/ahmetoner/whisper-asr-webservice)

```bash
docker run -d --gpus all -p 9000:9000 \
  -e ASR_MODEL=base \
  -e ASR_ENGINE=openai_whisper \
  -v $PWD/cache:/root/.cache/ \
  onerahmet/openai-whisper-asr-webservice:latest-gpu
```