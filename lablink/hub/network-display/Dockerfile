FROM node:alpine

WORKDIR /app

COPY server.js index.html app.js styles.css ./

ENV API_UPSTREAM=http://uapiclient:7000

EXPOSE 80

CMD ["node", "server.js"]
