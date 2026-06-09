FROM alpine:3.22

RUN apk add --no-cache dnsmasq gettext

COPY dnsmasq.conf /etc/dnsmasq.conf

CMD ["sh", "-c", "\
  envsubst < /etc/dnsmasq.conf > /tmp/dnsmasq.conf && \
  dnsmasq --no-daemon --log-facility=- --conf-file=/tmp/dnsmasq.conf \
"]