# TLS Certificate Generation

Generate self-signed certificates for development:

```bash
openssl req -x509 -nodes -days 730 -newkey rsa:4096 \
  -keyout ./key.pem -out ./cert.pem \
  -subj "/C=YOUR_COUNTRY/ST=YOUR_STATE/L=YOUR_CITY/O=YOUR_ORGANIZATION/OU=YOUR_ORG_UNIT/CN=your-domain.com/emailAddress=support@your-domain.com" \
  -addext "subjectAltName=DNS:localhost,DNS:your-domain.com,DNS:api.your-domain.com,IP:127.0.0.1"
```

Replace the placeholders with your actual values:
- YOUR_COUNTRY: Your country code (e.g., US, UK, CA)
- YOUR_STATE: Your state/province
- YOUR_CITY: Your city
- YOUR_ORGANIZATION: Your organization name
- YOUR_ORG_UNIT: Your organizational unit
- your-domain.com: Your actual domain
- support@your-domain.com: Your support email
