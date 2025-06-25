# ===== Base image =====
FROM python:3.12.3-slim-bookworm as base

# Установка Nginx, curl и сборочных инструментов
RUN apt update && apt install -y nginx curl build-essential \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm /etc/nginx/sites-enabled/default

# Установка Node.js и глобальных утилит
RUN curl -fsSL https://deb.nodesource.com/setup_21.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g corepack pm2

# ===== Аргументы окружения для фронта =====
ARG NEXT_PUBLIC_LEARNHOUSE_API_URL
ARG NEXT_PUBLIC_LEARNHOUSE_MULTI_ORG
ARG NEXT_PUBLIC_LEARNHOUSE_DEFAULT_ORG
ARG NEXT_PUBLIC_LEARNHOUSE_TOP_DOMAIN
ARG NEXT_PUBLIC_LEARNHOUSE_BACKEND_URL
ARG NEXT_PUBLIC_LEARNHOUSE_DOMAIN
ARG NEXTAUTH_SECRET
ARG NEXTAUTH_URL

# ===== Frontend Build =====
FROM base AS deps

WORKDIR /app/web
COPY ./apps/web/package.json ./apps/web/pnpm-lock.yaml* ./
COPY ./apps/web /app/web

# Установка переменных окружения для сборки
ENV NEXT_PUBLIC_LEARNHOUSE_API_URL=http://51.158.99.183/api/v1/
ENV NEXT_PUBLIC_LEARNHOUSE_MULTI_ORG=false
ENV NEXT_PUBLIC_LEARNHOUSE_DEFAULT_ORG=default
ENV NEXT_PUBLIC_LEARNHOUSE_TOP_DOMAIN=51.158.99.183
ENV NEXT_PUBLIC_LEARNHOUSE_BACKEND_URL=http://51.158.99.183/
ENV NEXT_PUBLIC_LEARNHOUSE_DOMAIN=51.158.99.183
ENV NEXTAUTH_SECRET=changeme
ENV NEXTAUTH_URL=http://51.158.99.183
# Очистка старых .env и сборка
RUN rm -f .env*
RUN if [ -f pnpm-lock.yaml ]; then corepack enable pnpm && pnpm i --frozen-lockfile && pnpm run build; \
    else echo "Lockfile not found." && exit 1; \
    fi

# ===== Финальный образ =====
FROM base as runner

# Создание пользователя
RUN addgroup --system --gid 1001 system \
    && adduser --system --uid 1001 app \
    && mkdir .next \
    && chown app:system .next

# Копирование frontend артефактов
COPY --from=deps /app/web/public ./app/web/public
COPY --from=deps --chown=app:system /app/web/.next/standalone ./app/web/
COPY --from=deps --chown=app:system /app/web/.next/static ./app/web/.next/static

# ===== Backend сборка =====
WORKDIR /app/api
COPY ./apps/api/uv.lock ./apps/api/pyproject.toml ./
RUN pip install --upgrade pip && pip install uv && uv sync
COPY ./apps/api ./

# ===== Финальная конфигурация =====
WORKDIR /app
COPY ./extra/nginx.conf /etc/nginx/conf.d/default.conf
ENV PORT=8000 LEARNHOUSE_PORT=9000 HOSTNAME=0.0.0.0
COPY ./extra/start.sh /app/start.sh
CMD ["sh", "start.sh"]
