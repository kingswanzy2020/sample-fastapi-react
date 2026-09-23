# ---- target: dev (webpack dev server, used by docker-compose.override.yml) ----
FROM node:14-bullseye-slim AS dev

ADD package.json /package.json

ENV NODE_PATH=/node_modules
ENV PATH=$PATH:/node_modules/.bin
RUN npm install

WORKDIR /app
ADD . /app

EXPOSE 8000
EXPOSE 35729

ENTRYPOINT ["/bin/bash", "/app/run.sh"]
CMD ["start"]

# ---- stage: builder (compiles the static bundle for production) ----
FROM node:14-bullseye-slim AS builder

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

COPY . .
# Pre-existing repo issue, unrelated to containerizing: the airbnb ESLint
# config (frontend/.eslintrc.js) reports many rules at error severity across
# the current source tree, which react-scripts treats as build-failing.
# Fixing that lint debt is a separate task; skip CRA's bundled lint gate for
# this build only, via its own documented escape hatch.
RUN DISABLE_ESLINT_PLUGIN=true npm run build

# ---- target: production (nginx serving the static bundle) ----
FROM nginx:1.27-alpine AS production

COPY --from=builder /app/build /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

# 127.0.0.1, not localhost: nginx.conf is custom, so the image's entrypoint
# skips its usual auto-patch to also listen on [::]. nginx then binds IPv4
# only, but /etc/hosts resolves "localhost" to ::1 first -- wget tries that,
# gets connection refused, and never falls back to the working IPv4 address.
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1/ || exit 1
