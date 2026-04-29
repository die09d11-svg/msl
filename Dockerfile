# Etapa 1: compilar frontend
FROM node:20 AS frontend-build

WORKDIR /app/frontend

COPY frontend/package*.json ./
RUN npm install

COPY frontend/ ./
RUN npm run build


# Etapa 2: backend Julia
FROM julia:1.10

WORKDIR /app

# Copiar entorno Julia primero para cachear dependencias
COPY backend/Project.toml /app/backend/Project.toml

RUN julia -e "using Pkg; \
    Pkg.activate(\"/app/backend\"); \
    Pkg.instantiate(); \
    Pkg.add([ \
        \"HTTP\", \
        \"JSON3\", \
        \"Images\", \
        \"ImageIO\", \
        \"FileIO\", \
        \"NIfTI\", \
        \"DICOM\", \
        \"CodecZlib\", \
        \"StatsBase\", \
        \"HypothesisTests\", \
        \"Distributions\", \
        \"MultivariateStats\", \
        \"DataFrames\", \
        \"XLSX\", \
        \"NativeFileDialog\" \
    ]);"

# Copiar código fuente
COPY backend /app/backend
COPY launcher /app/launcher
COPY installers /app/installers

# Copiar frontend compilado
COPY --from=frontend-build /app/frontend/build /app/frontend/build

EXPOSE 8000

CMD ["julia","--project=/app/backend","-t","auto","backend/server.jl"]