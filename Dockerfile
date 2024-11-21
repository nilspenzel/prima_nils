FROM node:20

RUN mkdir /motis
RUN mkdir -p /motis/data

COPY build /build
COPY migrations /build/migrations
COPY package.json /
COPY node_modules /node_modules

RUN touch /.env

CMD ["node", "/build"]
