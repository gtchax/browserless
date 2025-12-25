# Self-contained Dockerfile for cloud deployment (Sevalla, Render, etc.)
# Combines base and chrome Dockerfiles into a single build

FROM ubuntu:24.04

LABEL org.opencontainers.image.source=https://github.com/browserless/browserless

ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=America/Los_Angeles
ARG BLESS_USER_ID=999
ARG APP_DIR=/usr/src/app
ARG NODE_VERSION=v24.12.0
ARG NPM_VERSION=11.7.0

ENV NODE_VERSION=$NODE_VERSION
ENV NVM_DIR=/usr/src/.nvm
ENV NODE_PATH=$NVM_DIR/versions/node/$NODE_VERSION/bin
ENV PATH=$NODE_PATH:$PATH
ENV APP_DIR=$APP_DIR
ENV TZ=$TZ
ENV DEBIAN_FRONTEND=$DEBIAN_FRONTEND
ENV HOST=0.0.0.0
ENV PORT=3000
ENV LANG="C.UTF-8"
ENV NODE_ENV=production
ENV DEBUG_COLORS=true
ENV PUPPETEER_SKIP_DOWNLOAD=true
ENV PLAYWRIGHT_BROWSERS_PATH=/usr/local/bin/playwright-browsers

RUN mkdir -p $APP_DIR $NVM_DIR

WORKDIR $APP_DIR

# Copy all necessary files
COPY assets assets
COPY bin bin
COPY extensions extensions
COPY external external
COPY scripts scripts
COPY static static
COPY fonts fonts

COPY CHANGELOG.md .
COPY LICENSE .
COPY NOTICE.txt .
COPY package.json .
COPY package-lock.json .
COPY README.md .
COPY tsconfig.json .

# Install base dependencies (curl needed for health checks)
RUN apt-get update && apt-get install -y \
  ca-certificates \
  curl \
  dumb-init \
  git \
  gnupg \
  libu2f-udev \
  software-properties-common \
  ssh \
  wget \
  xvfb

# Install Node.js via nvm
RUN curl -sL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash && \
  . $NVM_DIR/nvm.sh && \
  nvm install $NODE_VERSION && \
  npm install -g npm@$NPM_VERSION

# Install Python (needed for some dependencies)
RUN add-apt-repository universe && apt-get update && \
  apt-get install -y python3 python3-pip python3-setuptools && \
  update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1 && \
  update-alternatives --install /usr/bin/python python /usr/bin/python3 1

# Create blessuser
RUN groupadd -r blessuser && useradd --uid ${BLESS_USER_ID} -r -g blessuser -G audio,video blessuser && \
  mkdir -p /home/blessuser/Downloads && \
  chown -R blessuser:blessuser /home/blessuser

# Install npm dependencies
RUN npm clean-install

# Copy source files (chrome routes only)
COPY src src/
RUN rm -r src/routes/
COPY src/routes/management src/routes/management/
COPY src/routes/chrome src/routes/chrome/

# Install fonts
RUN cp fonts/* /usr/share/fonts/truetype/ 2>/dev/null || true

RUN echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | debconf-set-selections && \
  apt-get -y -qq install software-properties-common && \
  apt-add-repository "deb https://archive.canonical.com/ubuntu $(lsb_release -sc) partner" || true && \
  apt-get -y -qq --no-install-recommends install \
  fontconfig \
  fonts-freefont-ttf \
  fonts-gfs-neohellenic \
  fonts-indic \
  fonts-ipafont-gothic \
  fonts-kacst \
  fonts-liberation \
  fonts-noto-cjk \
  fonts-noto-color-emoji \
  fonts-roboto \
  fonts-thai-tlwg \
  fonts-ubuntu \
  fonts-wqy-zenhei \
  fonts-open-sans || true

# Install Chrome with dependencies
RUN ./node_modules/playwright-core/cli.js install --with-deps chrome && \
  npm run build && \
  npm run build:function && \
  npm prune production && \
  npm run install:debugger && \
  chown -R blessuser:blessuser $APP_DIR && \
  fc-cache -f -v && \
  apt-get -qq clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/fonts/truetype/noto

USER blessuser

EXPOSE 3000

# Health check for container orchestration
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:3000/ || exit 1

# Start Xvfb for Chrome and run the application
CMD ["sh", "-c", "Xvfb :99 -screen 0 1024x768x16 -nolisten tcp -nolisten unix >/dev/null 2>&1 & export DISPLAY=:99 && exec dumb-init -- npm start"]
