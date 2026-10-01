# LIBRE TRANSLATE

## Tạo API Key bằng công cụ ltmanage
```bash
docker exec -it libretranslate ltmanage keys add 5000
```

## Kiểm tra danh sách key đã tạo
```bash
docker exec -it libretranslate ltmanage keys
```

## API Test

```bash
curl -X POST http://localhost:5000/translate \
  -H "Content-Type: application/json" \
  -H "api_key: YOUR_API_KEY_HERE" \
  -d '{"q": "Hello world", "source": "en", "target": "vi"}'
```