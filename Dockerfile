# syntax=docker/dockerfile:1

# ----------------------------------------------------------------- build ---
# Compile the SvelteKit app and reduce node_modules to production deps only.
FROM node:22-alpine AS build

WORKDIR /app

# Dependencies first, so this layer stays cached while only sources change.
# .npmrc sets engine-strict=true, so it has to be present for npm ci.
COPY package.json package-lock.json .npmrc ./
RUN npm ci

COPY . .
RUN npm run build && npm prune --omit=dev

# --------------------------------------------------------------- runtime ---
# At runtime the server needs only build/, the production node_modules and
# package.json, so none of the source or dev dependencies are copied over.
FROM node:22-alpine AS runtime

WORKDIR /app

ENV NODE_ENV=production \
    PORT=3000 \
    HOST=0.0.0.0

COPY --from=build --chown=node:node /app/package.json ./package.json
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/build ./build

# The node image ships an unprivileged "node" user (uid 1000).
USER node

EXPOSE 3000

# The diagnostic endpoint returns 503 until the database is reachable, which
# makes it a good readiness signal for the container itself.
HEALTHCHECK --interval=10s --timeout=5s --start-period=15s --retries=6 \
    CMD ["node", "-e", "fetch('http://127.0.0.1:' + (process.env.PORT || 3000) + '/api/marking-test').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"]

CMD ["node", "build"]
