FROM node:20-slim AS build
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci
COPY tsconfig.json ./
COPY src ./src
RUN npm run build && npm prune --omit=dev

FROM node:20-slim
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=8080
COPY --from=build /app/package.json ./
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
# Staging N3 benchmark seed (VPC job); no runtime effect on auth-service.
COPY scripts/seed_n3_staging_benchmark.bundle.cjs ./scripts/seed_n3_staging_benchmark.bundle.cjs
COPY scripts/run_n3_staging_benchmark_vpc.bundle.cjs ./scripts/run_n3_staging_benchmark_vpc.bundle.cjs
COPY scripts/staging_worker_http_invoke.mjs ./scripts/staging_worker_http_invoke.mjs
EXPOSE 8080
USER node
CMD ["node", "dist/index.js"]
