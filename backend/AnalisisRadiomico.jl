# AnalisisRadiomico.jl - VERSIÓN JULIA PURA (Sin PyCall)
# Módulo de análisis radiómico para imágenes médicas NIfTI y DICOM
# Basado en código MATLAB validado - VERSIÓN COMPLETA
# Autor: MSL Process Backend
# Fecha: 2025

using NIfTI
using DICOM
using Statistics
using StatsBase
using LinearAlgebra
using JSON3
using Base.Threads
using XLSX
using Dates
using CodecZlib  # Para leer archivos .nii.gz comprimidos

# ==============================================================================
# CONSTANTES GLOBALES
# ==============================================================================

const NIVELES_GRISES_GLCM = 256  # Niveles para GLCM
const MAX_RUN_LENGTH = 50        # Longitud máxima de run para GLRLM
const MAX_ZONE_SIZE = 1000       # Tamaño máximo de zona para GLSZM

# ==============================================================================
# FUNCIONES DE LECTURA DE ARCHIVOS
# ==============================================================================

"""
    detectar_tipo_archivo(filepath::String) -> Symbol

Detecta el tipo de archivo médico por extensión.
"""
function detectar_tipo_archivo(filepath::String)
    ext = lowercase(splitext(filepath)[2])
    
    if ext in [".nii", ".gz"]
        return :nifti
    elseif ext == ".dcm"
        return :dicom
    else
        return :unknown
    end
end

"""
    leer_volumen_nifti(filepath::String) -> (Array{Float64, 3}, Tuple{Float64, Float64, Float64})

Lee un archivo NIfTI y retorna el volumen 3D y las dimensiones de voxel.
"""
function leer_volumen_nifti(filepath::String)
    try
        if endswith(filepath, ".gz")
            decompressed = open(filepath, "r") do io
                transcode(GzipDecompressor, read(io))
            end
            
            temp_path = tempname() * ".nii"
            write(temp_path, decompressed)
            
            nii = niread(temp_path, mmap=false)
            volumen = Float64.(nii.raw)
            pixdim = nii.header.pixdim
            voxel_dims = (Float64(pixdim[2]), Float64(pixdim[3]), Float64(pixdim[4]))
            
            try
                sleep(0.05)
                rm(temp_path, force=true)
            catch
            end
            
            return volumen, voxel_dims
        else
            nii = niread(filepath, mmap=false)
            volumen = Float64.(nii.raw)
            pixdim = nii.header.pixdim
            voxel_dims = (Float64(pixdim[2]), Float64(pixdim[3]), Float64(pixdim[4]))
            
            return volumen, voxel_dims
        end
    catch e
        throw(ErrorException("Error leyendo NIfTI: $e"))
    end
end

"""
    leer_volumen_dicom(filepath::String) -> (Array{Float64, 3}, Tuple{Float64, Float64, Float64})

Lee un archivo DICOM y retorna el volumen 3D y las dimensiones de voxel.
"""
function leer_volumen_dicom(filepath::String)
    try
        dcm_data = dcm_parse(filepath)
        
        volumen = Float64.(dcm_data[(0x7fe0, 0x0010)])
        
        pixel_spacing = get(dcm_data, (0x0028, 0x0030), [1.0, 1.0])
        slice_thickness = get(dcm_data, (0x0018, 0x0050), 1.0)
        
        voxel_dims = (Float64(pixel_spacing[1]), Float64(pixel_spacing[2]), Float64(slice_thickness))
        
        if ndims(volumen) == 2
            volumen = reshape(volumen, size(volumen)..., 1)
        end
        
        return volumen, voxel_dims
        
    catch e
        throw(ErrorException("Error leyendo DICOM: $e"))
    end
end

# ==============================================================================
# CARACTERÍSTICAS DE PRIMER ORDEN (FIRST ORDER)
# ==============================================================================

"""
    calcular_first_order(voxeles::Vector{Float64}, V_voxel::Float64) -> Dict

Calcula características estadísticas de primer orden.
"""
function calcular_first_order(voxeles::Vector{Float64}, V_voxel::Float64)
    N = length(voxeles)
    
    if N == 0
        return Dict{String, Float64}()
    end
    
    # Estadísticas básicas
    media = mean(voxeles)
    varianza = var(voxeles)
    desv_std = sqrt(varianza)
    minimo = minimum(voxeles)
    maximo = maximum(voxeles)
    
    # Energía
    energia = sum(x -> x^2, voxeles)
    energia_total = V_voxel * energia
    
    # Histograma para entropía
    num_bins = 256
    bin_edges = range(minimo, maximo + eps(maximo), length=num_bins + 1)
    hist = fit(Histogram, voxeles, bin_edges)
    P = hist.weights
    p = P ./ N
    p_nonzero = p[p .> 0]
    
    entropia = -sum(p_nonzero .* log2.(p_nonzero))
    entropia_shannon = entropia
    
    # Percentiles
    percentiles = quantile(voxeles, [0.10, 0.25, 0.50, 0.75, 0.90])
    p10, p25, mediana, p75, p90 = percentiles
    
    # Momentos centrados
    diff_media = voxeles .- media
    
    # Rango intercuartil
    riq = p75 - p25
    
    # Otras métricas
    alcance = maximo - minimo
    dam = mean(abs.(diff_media))
    rms = sqrt(energia / N)
    asimetria = mean(diff_media.^3) / desv_std^3
    curtosis = mean(diff_media.^4) / varianza^2
    
    # Entropía de Rényi (α = 2)
    α = 2.0
    entropia_renyi = (1 / (1 - α)) * log2(sum(p_nonzero.^α))
    
    # Entropía normalizada
    entropia_normalizada = entropia / log2(num_bins)
    
    # Rango robusto
    rango_robusto = p90 - p10
    
    # Coeficiente de variación
    coef_variacion = desv_std / media
    
    # Coeficiente de dispersión cuartil
    coef_dispersion_cuartil = (p75 - p25) / (p75 + p25)
    
    # RMAD (Robust Mean Absolute Deviation)
    in_range = filter(x -> p10 <= x <= p90, voxeles)
    rmad = isempty(in_range) ? 0.0 : mean(abs.(in_range .- mean(in_range)))
    
    # Desviación absoluta de la mediana
    dam_mediana = mean(abs.(voxeles .- mediana))
    
    # Moda (aproximada como el bin con mayor frecuencia)
    moda_idx = argmax(P)
    moda = (bin_edges[moda_idx] + bin_edges[moda_idx + 1]) / 2
    
    return Dict{String, Float64}(
        "Media" => media,
        "Varianza" => varianza,
        "Desviacion_estandar" => desv_std,
        "Energia" => energia,
        "Max" => maximo,
        "Min" => minimo,
        "Energia_total" => energia_total,
        "Entropia" => entropia,
        "percentil_10" => p10,
        "percentil_25" => p25,
        "Mediana" => mediana,
        "percentil_75" => p75,
        "percentil_90" => p90,
        "Rango_intercuartil" => riq,
        "Alcance" => alcance,
        "Desviacion_absoluta_media" => dam,
        "Raiz_cuadrada_media" => rms,
        "Asimetria" => asimetria,
        "Curtosis" => curtosis,
        "Entropia_Shannon" => entropia_shannon,
        "Entropia_Renyi" => entropia_renyi,
        "Moda" => moda,
        "Coef_Variacion" => coef_variacion,
        "Entropia_Normalizada" => entropia_normalizada,
        "RMAD" => rmad,
        "Rango_Robusto" => rango_robusto,
        "Coef_Dispersion_Cuartil" => coef_dispersion_cuartil,
        "DAM_Mediana" => dam_mediana
    )
end

# ==============================================================================
# CARACTERÍSTICAS DE FORMA (SHAPE)
# ==============================================================================

"""
    calcular_shape(mask::BitArray{3}, voxel_dims::Tuple{Float64, Float64, Float64}) -> Dict

Calcula características de forma basadas en la máscara 3D.
"""
function calcular_shape(mask::BitArray{3}, voxel_dims::Tuple{Float64, Float64, Float64})
    pixel_x, pixel_y, pixel_z = voxel_dims
    V_voxel = pixel_x * pixel_y * pixel_z
    
    # Volumen total
    volumen = sum(mask) * V_voxel
    
    if volumen == 0
        return Dict{String, Float64}()
    end
    
    # Obtener coordenadas de voxels en la máscara
    indices = findall(mask)
    N = length(indices)
    
    coords = zeros(Float64, N, 3)
    for (i, idx) in enumerate(indices)
        coords[i, 1] = idx[1] * pixel_x
        coords[i, 2] = idx[2] * pixel_y
        coords[i, 3] = idx[3] * pixel_z
    end
    
    # Matriz de covarianza
    cov_matrix = cov(coords)
    
    # Autovalores (ordenados descendentemente)
    eigenvalues = sort(eigvals(cov_matrix), rev=true)
    λ1, λ2, λ3 = eigenvalues .+ eps()
    
    # Longitudes de ejes principales
    longitud_eje_mayor = 4 * sqrt(λ3)  # CORREGIDO: λ3 es el mayor en MATLAB
    longitud_eje_medio = 4 * sqrt(λ2)
    longitud_eje_menor = 4 * sqrt(λ1)  # CORREGIDO: λ1 es el menor en MATLAB
    
    # Elongación y planitud (según MATLAB)
    elongacion = sqrt(λ2 / λ3)
    planitud = sqrt(λ1 / λ3)
    
    # Superficie aproximada usando método de caras expuestas
    area_superficie = calcular_area_superficie_aproximada(mask, voxel_dims)
    
    # Esfericidad (fórmula de MATLAB)
    esfericidad = (π^(1/3) * (6 * volumen)^(2/3)) / (area_superficie + eps())
    
    # Compacidad
    compacidad_1 = volumen / sqrt(π * area_superficie^3)
    compacidad_2 = 36 * π * (volumen^2 / area_superficie^3)
    
    # Surface to volume ratio
    surface_to_volume_ratio = area_superficie / volumen
    
    return Dict{String, Float64}(
        "Volumen" => volumen,
        "Longitud_del_eje_mayor" => longitud_eje_mayor,
        "Longitud_del_eje_medio" => longitud_eje_medio,
        "Longitud_del_eje_menor" => longitud_eje_menor,
        "Elongacion" => elongacion,
        "Planitud" => planitud,
        "Area_superficie" => area_superficie,
        "Esfericidad" => esfericidad,
        "Compacidad_1" => compacidad_1,
        "Compacidad_2" => compacidad_2,
        "surface_to_volume_ratio" => surface_to_volume_ratio
    )
end

"""
    calcular_area_superficie_aproximada(mask::BitArray{3}, voxel_dims::Tuple) -> Float64

Calcula área de superficie aproximada contando caras expuestas.
"""
function calcular_area_superficie_aproximada(mask::BitArray{3}, voxel_dims::Tuple{Float64, Float64, Float64})
    nx, ny, nz = size(mask)
    px, py, pz = voxel_dims
    
    area = 0.0
    
    # Cara XY (arriba/abajo)
    area_xy = px * py
    # Cara XZ (adelante/atrás)
    area_xz = px * pz
    # Cara YZ (izquierda/derecha)
    area_yz = py * pz
    
    @inbounds for i in 1:nx, j in 1:ny, k in 1:nz
        if mask[i, j, k]
            # Verificar vecinos en 6-conectividad
            # Dirección X
            if i == 1 || !mask[i-1, j, k]
                area += area_yz
            end
            if i == nx || !mask[i+1, j, k]
                area += area_yz
            end
            
            # Dirección Y
            if j == 1 || !mask[i, j-1, k]
                area += area_xz
            end
            if j == ny || !mask[i, j+1, k]
                area += area_xz
            end
            
            # Dirección Z
            if k == 1 || !mask[i, j, k-1]
                area += area_xy
            end
            if k == nz || !mask[i, j, k+1]
                area += area_xy
            end
        end
    end
    
    return area
end

# ==============================================================================
# GLCM (GRAY LEVEL CO-OCCURRENCE MATRIX)
# ==============================================================================

"""
    calcular_glcm(V_norm::Array{UInt8, 3}, Ng::Int) -> Matrix{Float64}

Calcula la matriz GLCM acumulada para todo el volumen 3D.
"""
function calcular_glcm(V_norm::Array{UInt8, 3}, Ng::Int)
    num_slices = size(V_norm, 3)
    glcm_total = zeros(Float64, Ng, Ng)
    
    for slice_idx in 1:num_slices
        slice = @view V_norm[:, :, slice_idx]
        glcm_slice = calcular_glcm_slice(slice, Ng)
        glcm_total .+= glcm_slice
    end
    
    suma = sum(glcm_total)
    if suma > 0
        glcm_total ./= suma
    end
    
    return glcm_total
end

"""
    calcular_glcm_slice(slice::AbstractMatrix{UInt8}, Ng::Int) -> Matrix{Float64}

Calcula GLCM para un slice 2D con offset [0,1].
"""
function calcular_glcm_slice(slice::AbstractMatrix{UInt8}, Ng::Int)
    rows, cols = size(slice)
    glcm = zeros(Float64, Ng, Ng)
    
    @inbounds for i in 1:rows
        for j in 1:(cols-1)
            val1 = Int(slice[i, j]) + 1
            val2 = Int(slice[i, j+1]) + 1
            
            if 1 <= val1 <= Ng && 1 <= val2 <= Ng
                glcm[val1, val2] += 1.0
            end
        end
    end
    
    return glcm
end

"""
    calcular_features_glcm(glcm::Matrix{Float64}) -> Dict

Calcula todas las características derivadas de la matriz GLCM.
"""
function calcular_features_glcm(glcm::Matrix{Float64})
    Ng = size(glcm, 1)
    
    # Índices i, j
    I = repeat(0:(Ng-1), 1, Ng)
    J = I'
    
    # Probabilidades marginales
    px = vec(sum(glcm, dims=2))
    py = vec(sum(glcm, dims=1))
    
    # Medias
    μ_i = sum(I .* glcm)
    μ_j = sum(J .* glcm)
    
    # Diferencias centradas
    I_cent = I .- μ_i
    J_cent = J .- μ_j
    
    # Desviaciones estándar
    σ_i = sqrt(sum(I_cent.^2 .* glcm))
    σ_j = sqrt(sum(J_cent.^2 .* glcm))
    
    # Diferencias absolutas y cuadradas
    diff_abs = abs.(I .- J)
    diff_sq = (I .- J).^2
    
    # Características básicas
    autocorrelacion = sum(I .* J .* glcm)
    contraste = sum(diff_sq .* glcm)
    correlacion = sum(I_cent .* J_cent .* glcm) / (σ_i * σ_j + eps())
    homogeneidad = sum(glcm ./ (1 .+ diff_abs))
    energia_conjunta = sum(glcm.^2)
    entropia_conjunta = -sum(glcm .* log2.(glcm .+ eps()))
    
    # Diferencias
    p_diff = zeros(Float64, Ng)
    for i in 1:Ng, j in 1:Ng
        k = Int(diff_abs[i, j]) + 1
        if k <= Ng
            p_diff[k] += glcm[i, j]
        end
    end
    suma_diff = sum(p_diff)
    if suma_diff > 0
        p_diff ./= suma_diff
    end
    
    k_vals = 0:(Ng-1)
    diferencia_media = sum(k_vals .* p_diff)
    entropia_diferencia = -sum(p_diff .* log2.(p_diff .+ eps()))
    varianza_diferencia = sum((k_vals .- diferencia_media).^2 .* p_diff)
    
    # Prominencia y sombra de cluster
    sum_cent = I .+ J .- μ_i .- μ_j
    prominencia_cluster = sum(sum_cent.^4 .* glcm)
    sombra_cluster = sum(sum_cent.^3 .* glcm)
    
    # Entropías
    HX = -sum(px .* log2.(px .+ eps()))
    HY = -sum(py .* log2.(py .+ eps()))
    HXY = entropia_conjunta
    
    px_py = px * py'
    HXY1 = -sum(glcm .* log2.(px_py .+ eps()))
    HXY2 = -sum(px_py .* log2.(px_py .+ eps()))
    
    IMC1 = (HXY - HXY1) / max(HX, HY)
    IMC2 = sqrt(max(0, 1 - exp(-2 * (HXY2 - HXY))))
    
    # IDM y IDMN
    IDM = sum(glcm ./ (1 .+ diff_sq))
    IDMN = sum(glcm ./ (1 .+ diff_sq / (Ng - 1)^2))
    
    probabilidad_maxima = maximum(glcm)
    
    return Dict{String, Float64}(
        "Autocorrelacion" => autocorrelacion,
        "Contraste" => contraste,
        "Correlacion" => correlacion,
        "Homogeneidad" => homogeneidad,
        "Energia_Conjunta" => energia_conjunta,
        "Entropia_Conjunta" => entropia_conjunta,
        "Diferencia_Media" => diferencia_media,
        "Entropia_Diferencia" => entropia_diferencia,
        "Varianza_Diferencia" => varianza_diferencia,
        "Prominencia_Cluster" => prominencia_cluster,
        "Sombra_Cluster" => sombra_cluster,
        "IMC1" => IMC1,
        "IMC2" => IMC2,
        "IDM" => IDM,
        "IDMN" => IDMN,
        "Probabilidad_Maxima" => probabilidad_maxima
    )
end

# ==============================================================================
# GLRLM (GRAY LEVEL RUN LENGTH MATRIX)
# ==============================================================================

"""
    calcular_glrlm(V_norm::Array{UInt8, 3}, Ng::Int, max_run::Int) -> Matrix{Float64}

Calcula GLRLM acumulada para todo el volumen.
"""
function calcular_glrlm(V_norm::Array{UInt8, 3}, Ng::Int, max_run::Int)
    num_slices = size(V_norm, 3)
    glrlm_total = zeros(Float64, Ng, max_run)
    
    for slice_idx in 1:num_slices
        slice = @view V_norm[:, :, slice_idx]
        glrlm_slice = calcular_glrlm_slice(slice, Ng, max_run)
        glrlm_total .+= glrlm_slice
    end
    
    suma = sum(glrlm_total)
    if suma > 0
        glrlm_total ./= suma
    end
    
    return glrlm_total
end

"""
    calcular_glrlm_slice(slice::AbstractMatrix{UInt8}, Ng::Int, max_run::Int) -> Matrix{Float64}

Calcula GLRLM para un slice 2D procesando runs horizontales.
"""
function calcular_glrlm_slice(slice::AbstractMatrix{UInt8}, Ng::Int, max_run::Int)
    rows, cols = size(slice)
    glrlm = zeros(Float64, Ng, max_run)
    
    @inbounds for row in 1:rows
        col = 1
        while col <= cols
            val = Int(slice[row, col]) + 1
            
            if val > 0 && val <= Ng
                run_length = 1
                while col + run_length <= cols && slice[row, col + run_length] == slice[row, col]
                    run_length += 1
                end
                
                if run_length <= max_run
                    glrlm[val, run_length] += 1.0
                end
                
                col += run_length
            else
                col += 1
            end
        end
    end
    
    return glrlm
end

"""
    calcular_features_glrlm(glrlm::Matrix{Float64}, num_voxels::Int) -> Dict

Calcula características derivadas de GLRLM - VERSIÓN COMPLETA CON TODAS LAS MÉTRICAS.
"""
function calcular_features_glrlm(glrlm::Matrix{Float64}, num_voxels::Int)
    Ng, Nr = size(glrlm)
    
    i_vals = 1:Ng
    j_vals = 1:Nr
    
    # Sumas marginales
    sum_gray = vec(sum(glrlm, dims=2))
    sum_run = vec(sum(glrlm, dims=1))
    
    # Normalizar para obtener pij
    total = sum(glrlm)
    pij = glrlm / total
    
    # SRE y LRE
    j_sq = j_vals.^2
    SRE = sum(pij ./ j_sq')
    LRE = sum(pij .* j_sq')
    
    # GLN y RLN
    GLN = sum(sum_gray.^2)
    RLN = sum(sum_run.^2)
    
    # RP (Run Percentage)
    total_runs = sum(glrlm)
    RP = total_runs / num_voxels
    
    # LGRE y HGRE (usando niveles de gris originales)
    i_sq = i_vals.^2
    LGRE = sum(pij ./ i_sq)
    HGRE = sum(pij .* i_sq)
    
    # Medias
    μ_i = sum(i_vals .* sum_gray)
    μ_j = sum(j_vals .* sum_run)
    
    # Varianzas
    gray_level_variance = sum((i_vals .- μ_i).^2 .* sum_gray)
    run_length_variance = sum((j_vals .- μ_j).^2 .* sum_run)
    
    # Entropía y uniformidad
    entropy = -sum(pij .* log2.(pij .+ eps()))
    uniformity = sum(pij.^2)
    
    # ========== MÉTRICAS COMPUESTAS (FALTANTES) ==========
    
    # 1. LowGrayLevelRunEmphasis2 (versión alternativa usando Ng - i + 1)
    low_gray_emphasis2 = sum(pij ./ i_vals)
    
    # 2. HighGrayLevelRunEmphasis2 (versión alternativa)
    high_gray_emphasis2 = sum(pij .* (Ng .- i_vals .+ 1))
    
    # 3. ShortRunHighGrayLevelEmphasis
    short_run_high_gray = sum(pij ./ j_sq' .* (Ng .- i_vals .+ 1))
    
    # 4. LongRunLowGrayLevelEmphasis
    long_run_low_gray = sum(pij .* j_sq' .* i_vals)
    
    # 5. ShortRunLowGrayLevelEmphasis
    short_run_low_gray = sum(pij ./ j_sq' ./ i_sq)
    
    # 6. LongRunHighGrayLevelEmphasis
    long_run_high_gray = sum(pij .* j_sq' .* i_sq)
    
    return Dict{String, Float64}(
        "SRE" => SRE,
        "LRE" => LRE,
        "GLN" => GLN,
        "RLN" => RLN,
        "RP" => RP,
        "LGRE" => LGRE,
        "HGRE" => HGRE,
        "GrayLevelVariance" => gray_level_variance,
        "RunLengthVariance" => run_length_variance,
        "GrayLevelMean" => μ_i,
        "RunLengthMean" => μ_j,
        "Entropy" => entropy,
        "Uniformity" => uniformity,
        # Métricas adicionales (como en MATLAB)
        "LowGrayLevelRunEmphasis2" => low_gray_emphasis2,
        "HighGrayLevelRunEmphasis2" => high_gray_emphasis2,
        "ShortRunHighGrayLevelEmphasis" => short_run_high_gray,
        "LongRunLowGrayLevelEmphasis" => long_run_low_gray,
        "ShortRunLowGrayLevelEmphasis" => short_run_low_gray,
        "LongRunHighGrayLevelEmphasis" => long_run_high_gray
    )
end

# ==============================================================================
# GLSZM (GRAY LEVEL SIZE ZONE MATRIX)
# ==============================================================================

"""
    calcular_glszm(V_norm::Array{UInt8, 3}, Ng::Int) -> Matrix{Float64}

Calcula GLSZM acumulada usando connected components en cada slice.
"""
function calcular_glszm(V_norm::Array{UInt8, 3}, Ng::Int)
    num_slices = size(V_norm, 3)
    max_zone = min(MAX_ZONE_SIZE, prod(size(V_norm)[1:2]))
    glszm_total = zeros(Float64, Ng, max_zone)
    
    for slice_idx in 1:num_slices
        slice = @view V_norm[:, :, slice_idx]
        glszm_slice = calcular_glszm_slice(slice, Ng)
        
        if size(glszm_slice, 2) > size(glszm_total, 2)
            new_size = size(glszm_slice, 2)
            glszm_total = hcat(glszm_total, zeros(Ng, new_size - size(glszm_total, 2)))
        end
        
        glszm_total[:, 1:size(glszm_slice, 2)] .+= glszm_slice
    end
    
    # Recortar columnas vacías
    last_col = findlast(any(glszm_total .> 0, dims=1)[:])
    if last_col !== nothing
        glszm_total = glszm_total[:, 1:last_col]
    end
    
    suma = sum(glszm_total)
    if suma > 0
        glszm_total ./= suma
    end
    
    return glszm_total
end

"""
    calcular_glszm_slice(slice::AbstractMatrix{UInt8}, Ng::Int) -> Matrix{Float64}

Calcula GLSZM para un slice 2D usando flood-fill para encontrar zonas conectadas.
"""
function calcular_glszm_slice(slice::AbstractMatrix{UInt8}, Ng::Int)
    rows, cols = size(slice)
    max_size = rows * cols
    glszm = zeros(Float64, Ng, max_size)
    visited = falses(size(slice))
    
    @inbounds for i in 1:rows, j in 1:cols
        if !visited[i, j]
            val = Int(slice[i, j]) + 1
            
            if val > 0 && val <= Ng
                target_val = UInt8(slice[i, j])
                
                # Flood-fill para encontrar zona conectada
                zone_size = flood_fill!(visited, slice, i, j, target_val)
                
                if zone_size > 0 && zone_size <= max_size
                    glszm[val, zone_size] += 1.0
                end
            end
        end
    end
    
    # Recortar columnas vacías
    last_col = findlast(any(glszm .> 0, dims=1)[:])
    if last_col === nothing
        return zeros(Float64, Ng, 1)
    end
    
    return glszm[:, 1:last_col]
end

"""
    flood_fill!(visited::BitArray{2}, slice::AbstractMatrix{UInt8}, i::Int, j::Int, target_val::UInt8) -> Int

Implementación de flood-fill 8-conectado para encontrar zonas del mismo valor.
"""
function flood_fill!(visited::BitArray{2}, slice::AbstractMatrix{UInt8}, i::Int, j::Int, target_val::UInt8)
    rows, cols = size(slice)
    stack = [(i, j)]
    zone_size = 0
    
    while !isempty(stack)
        ci, cj = pop!(stack)
        
        if ci < 1 || ci > rows || cj < 1 || cj > cols || visited[ci, cj]
            continue
        end
        
        if slice[ci, cj] != target_val
            continue
        end
        
        visited[ci, cj] = true
        zone_size += 1
        
        # Agregar vecinos 8-conectados
        if ci > 1
            push!(stack, (ci-1, cj))
            if cj > 1
                push!(stack, (ci-1, cj-1))
            end
            if cj < cols
                push!(stack, (ci-1, cj+1))
            end
        end
        
        if ci < rows
            push!(stack, (ci+1, cj))
            if cj > 1
                push!(stack, (ci+1, cj-1))
            end
            if cj < cols
                push!(stack, (ci+1, cj+1))
            end
        end
        
        if cj > 1
            push!(stack, (ci, cj-1))
        end
        
        if cj < cols
            push!(stack, (ci, cj+1))
        end
    end
    
    return zone_size
end

"""
    calcular_features_glszm(glszm::Matrix{Float64}, num_voxels::Int) -> Dict

Calcula características derivadas de GLSZM - VERSIÓN COMPLETA CON TODAS LAS MÉTRICAS.
"""
function calcular_features_glszm(glszm::Matrix{Float64}, num_voxels::Int)
    Ng, Ns = size(glszm)
    
    i_vals = 1:Ng
    j_vals = 1:Ns
    
    # Sumas marginales
    sum_gray = vec(sum(glszm, dims=2))
    sum_zone = vec(sum(glszm, dims=1))
    
    # Normalizar para obtener pij
    total = sum(glszm)
    pij = glszm / total
    
    # SZE y LZE
    j_sq = j_vals.^2
    SZE = sum(pij ./ j_sq')
    LZE = sum(pij .* j_sq')
    
    # GLN y ZSN
    GLN_GLSZM = sum(sum_gray.^2)
    ZSN = sum(sum_zone.^2)
    
    # LGZE y HGZE
    i_sq = i_vals.^2
    LGZE = sum(pij ./ i_sq)
    HGZE = sum(pij .* i_sq)
    
    # Zone Percentage
    total_zones = sum(glszm)
    zone_percentage = total_zones / num_voxels
    
    # Medias
    μ_i = sum(i_vals .* sum_gray)
    μ_j = sum(j_vals .* sum_zone)
    
    # Varianzas
    gray_level_variance = sum((i_vals .- μ_i).^2 .* sum_gray)
    zone_size_variance = sum((j_vals .- μ_j).^2 .* sum_zone)
    
    # Entropía y uniformidad
    entropy = -sum(pij .* log2.(pij .+ eps()))
    uniformity = sum(pij.^2)
    
    # ========== MÉTRICAS COMPUESTAS (FALTANTES) ==========
    
    # 1. SmallZoneHighGrayLevelEmphasis
    small_zone_high_gray = sum(pij ./ j_sq' .* (Ng .- i_vals .+ 1))
    
    # 2. LargeZoneLowGrayLevelEmphasis
    large_zone_low_gray = sum(pij .* j_sq' .* i_vals)
    
    # 3. SmallZoneLowGrayLevelEmphasis
    small_zone_low_gray = sum(pij ./ j_sq' ./ i_sq)
    
    # 4. LargeZoneHighGrayLevelEmphasis
    large_zone_high_gray = sum(pij .* j_sq' .* i_sq)
    
    # 5. GrayLevelNonUniformityNormalized
    gray_level_non_uniformity_normalized = sum(sum_gray.^2) / total
    
    return Dict{String, Float64}(
        "SZE" => SZE,
        "LZE" => LZE,
        "GLN_GLSZM" => GLN_GLSZM,
        "ZSN" => ZSN,
        "LGZE" => LGZE,
        "HGZE" => HGZE,
        "ZonePercentage" => zone_percentage,
        "GrayLevelVariance_GLSZM" => gray_level_variance,
        "ZoneSizeVariance" => zone_size_variance,
        "Entropy_GLSZM" => entropy,
        "Uniformity_GLSZM" => uniformity,
        # Métricas adicionales (como en MATLAB)
        "SmallZoneHighGrayLevelEmphasis" => small_zone_high_gray,
        "LargeZoneLowGrayLevelEmphasis" => large_zone_low_gray,
        "SmallZoneLowGrayLevelEmphasis" => small_zone_low_gray,
        "LargeZoneHighGrayLevelEmphasis" => large_zone_high_gray,
        "GrayLevelNonUniformityNormalized" => gray_level_non_uniformity_normalized
    )
end

# ==============================================================================
# FUNCIÓN PRINCIPAL DE EXTRACCIÓN
# ==============================================================================

"""
    extraer_features_archivo(filepath::String) -> Dict

Extrae todas las características radiómicas de un archivo individual.
"""
function extraer_features_archivo(filepath::String)
    nombre_archivo = basename(filepath)
    
    try
        println("  📊 Procesando: $nombre_archivo")
        
        if !isfile(filepath)
            return Dict(
                "archivo" => nombre_archivo,
                "success" => false,
                "error" => "Archivo no encontrado"
            )
        end
        
        tipo = detectar_tipo_archivo(filepath)
        
        if tipo == :unknown
            return Dict(
                "archivo" => nombre_archivo,
                "success" => false,
                "error" => "Formato no soportado"
            )
        end
        
        println("    📂 Leyendo volumen...")
        if tipo == :nifti
            volumen, voxel_dims = leer_volumen_nifti(filepath)
        else
            volumen, voxel_dims = leer_volumen_dicom(filepath)
        end
        
        V_voxel = prod(voxel_dims)
        
        println("    🎭 Creando máscara...")
        mask = volumen .> 0
        voxeles = volumen[mask]
        
        filter!(!isnan, voxeles)
        filter!(!isinf, voxeles)
        
        if isempty(voxeles)
            return Dict(
                "archivo" => nombre_archivo,
                "success" => false,
                "error" => "No hay voxels válidos en la imagen"
            )
        end
        
        println("    🔢 Normalizando...")
        min_val, max_val = extrema(volumen)
        rango = max_val - min_val
        V_norm = UInt8.(round.((volumen .- min_val) ./ rango .* 255))
        
        num_voxels_total = length(V_norm)
        
        caracteristicas = Dict{String, Any}()
        
        println("    📈 Calculando First Order...")
        caracteristicas["first_order"] = calcular_first_order(voxeles, V_voxel)
        
        println("    📐 Calculando Shape...")
        caracteristicas["shape"] = calcular_shape(mask, voxel_dims)
        
        println("    🔲 Calculando GLCM...")
        glcm = calcular_glcm(V_norm, NIVELES_GRISES_GLCM)
        caracteristicas["texture_glcm"] = calcular_features_glcm(glcm)
        
        println("    🏃 Calculando GLRLM...")
        glrlm = calcular_glrlm(V_norm, NIVELES_GRISES_GLCM, MAX_RUN_LENGTH)
        caracteristicas["texture_glrlm"] = calcular_features_glrlm(glrlm, num_voxels_total)
        
        println("    🔳 Calculando GLSZM...")
        glszm = calcular_glszm(V_norm, NIVELES_GRISES_GLCM)
        caracteristicas["texture_glszm"] = calcular_features_glszm(glszm, num_voxels_total)
        
        num_features = sum(length(v) for v in values(caracteristicas))
        
        println("    ✅ Completado: $num_features características extraídas")
        
        return Dict(
            "archivo" => nombre_archivo,
            "success" => true,
            "num_caracteristicas" => num_features,
            "caracteristicas" => caracteristicas
        )
        
    catch e
        println("    ❌ Error: $e")
        return Dict(
            "archivo" => nombre_archivo,
            "success" => false,
            "error" => string(e),
            "num_caracteristicas" => 0
        )
    end
end

# ==============================================================================
# FUNCIÓN PRINCIPAL: ANALIZAR_RADIOMICO
# ==============================================================================

"""
    analizar_radiomico(archivos::Vector{String}, modo_paralelo::Bool=false) -> Dict

Función principal de análisis radiómico - 100% Julia puro.
"""
function analizar_radiomico(archivos::Vector{String}, modo_paralelo::Bool=false)
    println("\n" * "="^70)
    println(" ANÁLISIS RADIÓMICO - Julia ")
    println("="^70)
    println(" Archivos a procesar: $(length(archivos))")
    println("  Modo: $(modo_paralelo ? "Paralelo ($(nthreads()) threads)" : "Lineal")")
    println("="^70 * "\n")
    
    if isempty(archivos)
        return Dict(
            "success" => false,
            "error" => "No se proporcionaron archivos para procesar",
            "resultados" => [],
            "tiempo_total" => 0.0,
            "modo_usado" => "none",
            "archivos_procesados" => 0,
            "archivos_exitosos" => 0,
            "archivos_fallidos" => 0
        )
    end
    
    tiempo_inicio = time()
    
    resultados = Vector{Dict{String, Any}}(undef, length(archivos))
    
    if modo_paralelo && nthreads() > 1
        println("== Iniciando procesamiento paralelo...\n")
        
        @threads for i in 1:length(archivos)
            println(" Thread $(threadid()): Procesando archivo $i de $(length(archivos))")
            resultados[i] = extraer_features_archivo(archivos[i])
        end
        
    else
        println("== Iniciando procesamiento secuencial...\n")
        
        for i in 1:length(archivos)
            println(" Procesando archivo $i de $(length(archivos))")
            resultados[i] = extraer_features_archivo(archivos[i])
        end
    end
    
    tiempo_total = time() - tiempo_inicio
    
    archivos_exitosos = count(r -> r["success"], resultados)
    archivos_fallidos = length(resultados) - archivos_exitosos
    
    success_global = archivos_exitosos > 0
    
    println("\n" * "="^70)
    println("✅ ANÁLISIS COMPLETADO")
    println("="^70)
    println("⏱️  Tiempo total: $(round(tiempo_total, digits=2)) segundos")
    println("📊 Archivos procesados: $(length(archivos))")
    println("✅ Exitosos: $archivos_exitosos")
    println("❌ Fallidos: $archivos_fallidos")
    println("⚡ Modo usado: $(modo_paralelo ? "paralelo" : "lineal")")
    if archivos_exitosos > 0
        tiempo_promedio = tiempo_total / archivos_exitosos
        println("📈 Tiempo promedio por archivo: $(round(tiempo_promedio, digits=2)) segundos")
    end
    println("="^70 * "\n")
    
    return Dict(
        "success" => success_global,
        "resultados" => resultados,
        "tiempo_total" => round(tiempo_total, digits=2),
        "modo_usado" => modo_paralelo ? "paralelo" : "lineal",
        "archivos_procesados" => length(archivos),
        "archivos_exitosos" => archivos_exitosos,
        "archivos_fallidos" => archivos_fallidos,
        "implementacion" => "Julia Puro (sin PyCall)"
    )
end

# ==============================================================================
# FUNCIONES AUXILIARES DE UTILIDAD
# ==============================================================================

"""
    guardar_resultados_radiomicos_excel(result::Dict, base_resultados::String) -> String

Guarda los resultados del análisis radiómico en formato Excel.
"""
function guardar_resultados_radiomicos_excel(result::Dict, base_resultados::String)
    try
        dir_resultados = joinpath(base_resultados, "radiomics")
        mkpath(dir_resultados)
        
        timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
        nombre_archivo = "radiomics_$(timestamp).xlsx"
        ruta_completa = joinpath(dir_resultados, nombre_archivo)
        
        println("📊 Generando archivo Excel: $nombre_archivo")
        
        resultados = get(result, "resultados", [])
        
        # Recopilar TODAS las features únicas con NOMBRES LIMPIOS
        todas_features_list = String[]
        feature_categoria_map = Dict{String, String}()

        for resultado in resultados
            if get(resultado, "success", false)
                caracteristicas = get(resultado, "caracteristicas", Dict())
                for (categoria, features) in caracteristicas
                    for feature_name in keys(features)
                        if !(feature_name in todas_features_list)
                            push!(todas_features_list, feature_name)
                            feature_categoria_map[feature_name] = categoria
                        end
                    end
                end
            end
        end
        
        sort!(todas_features_list)
        
        nombres_archivos = [get(r, "archivo", "Unknown") for r in resultados]
        
        println("     $(length(todas_features_list)) features × $(length(nombres_archivos)) archivos")
        
        XLSX.openxlsx(ruta_completa, mode="w") do xf
            # HOJA 1: DATOS
            sheet_datos = xf[1]
            XLSX.rename!(sheet_datos, "Datos")
            
            sheet_datos[XLSX.CellRef(1, 1)] = "Feature"
            sheet_datos[XLSX.CellRef(1, 2)] = "Categoria"
            
            for (idx, nombre_archivo) in enumerate(nombres_archivos)
                sheet_datos[XLSX.CellRef(1, idx + 2)] = nombre_archivo
            end
            
            for (row_idx, feature_name) in enumerate(todas_features_list)
                fila = row_idx + 1
                
                sheet_datos[XLSX.CellRef(fila, 1)] = feature_name
                sheet_datos[XLSX.CellRef(fila, 2)] = get(feature_categoria_map, feature_name, "")
                
                for (col_idx, resultado) in enumerate(resultados)
                    col = col_idx + 2
    
                    if get(resultado, "success", false)
                        caracteristicas = get(resultado, "caracteristicas", Dict())
        
                        valor_encontrado = false
                        for (categoria, features) in caracteristicas
                            for (fname, valor) in features
                                if fname == feature_name
                                    valor_numerico = try
                                        Float64(valor)
                                    catch
                                        NaN
                                    end
                                    sheet_datos[XLSX.CellRef(fila, col)] = valor_numerico
                                    valor_encontrado = true
                                    break
                                end
                            end
                            if valor_encontrado
                                break
                            end
                        end
                        
                        if !valor_encontrado
                            sheet_datos[XLSX.CellRef(fila, col)] = NaN
                        end
                    else
                        sheet_datos[XLSX.CellRef(fila, col)] = NaN
                    end
                end
            end
            
            # HOJA 2: RESUMEN
            XLSX.addsheet!(xf, "Resumen")
            sheet_resumen = xf["Resumen"]
            
            sheet_resumen["A1"] = "ANÁLISIS RADIÓMICO - RESUMEN"
            sheet_resumen["A2"] = "Generado: $(Dates.format(now(), "dd/mm/yyyy HH:MM:SS"))"
            
            row = 4
            sheet_resumen["A$(row)"] = "Métrica"
            sheet_resumen["B$(row)"] = "Valor"
            
            row += 1
            sheet_resumen["A$(row)"] = "Tiempo total (segundos)"
            sheet_resumen["B$(row)"] = get(result, "tiempo_total", 0.0)
            
            row += 1
            sheet_resumen["A$(row)"] = "Archivos procesados"
            sheet_resumen["B$(row)"] = get(result, "archivos_procesados", 0)
            
            row += 1
            sheet_resumen["A$(row)"] = "Archivos exitosos"
            sheet_resumen["B$(row)"] = get(result, "archivos_exitosos", 0)
            
            row += 1
            sheet_resumen["A$(row)"] = "Archivos fallidos"
            sheet_resumen["B$(row)"] = get(result, "archivos_fallidos", 0)
            
            row += 1
            sheet_resumen["A$(row)"] = "Total de features"
            sheet_resumen["B$(row)"] = length(todas_features_list)
            
            row += 2
            sheet_resumen["A$(row)"] = "ESTADO POR ARCHIVO"
            
            row += 1
            sheet_resumen["A$(row)"] = "Archivo"
            sheet_resumen["B$(row)"] = "Estado"
            sheet_resumen["C$(row)"] = "Error (si aplica)"
            
            for resultado in resultados
                row += 1
                sheet_resumen["A$(row)"] = get(resultado, "archivo", "")
                sheet_resumen["B$(row)"] = get(resultado, "success", false) ? "✓ OK" : "✗ ERROR"
                sheet_resumen["C$(row)"] = get(resultado, "error", "")
            end
            
            XLSX.setcolwidth!(sheet_datos, "A:A", 40)
            XLSX.setcolwidth!(sheet_datos, "B:B", 20)
            XLSX.setcolwidth!(sheet_resumen, "A:C", 25)
        end
        
        println("✅ Archivo Excel guardado: $ruta_completa")
        println("      Ubicación: $dir_resultados")
        
        return ruta_completa
        
    catch e
        println("❌ Error guardando archivo Excel: $e")
        println(stacktrace(catch_backtrace()))
        throw(e)
    end
end

"""
    exportar_resultados_csv(resultados::Dict, output_path::String)

Exporta resultados a CSV para análisis en Excel/R/Python.
"""
function exportar_resultados_csv(resultados::Dict, output_path::String)
    try
        open(output_path, "w") do io
            println(io, "Archivo,Categoria,Feature,Valor")
            
            for resultado in resultados["resultados"]
                if resultado["success"]
                    archivo = resultado["archivo"]
                    caracteristicas = resultado["caracteristicas"]
                    
                    for (categoria, features) in caracteristicas
                        for (feature_name, valor) in features
                            println(io, "$archivo,$categoria,$feature_name,$valor")
                        end
                    end
                end
            end
        end
        
        println("   CSV exportado: $output_path")
        return true
        
    catch e
        println("❌ Error exportando CSV: $e")
        return false
    end
end

"""
    obtener_resumen_features(resultados::Dict) -> Dict

Genera un resumen de las características extraídas.
"""
function obtener_resumen_features(resultados::Dict)
    if !resultados["success"] || isempty(resultados["resultados"])
        return Dict("error" => "No hay resultados exitosos")
    end
    
    resumen = Dict{String, Any}()
    categorias_count = Dict{String, Int}()
    
    for resultado in resultados["resultados"]
        if resultado["success"]
            for (categoria, features) in resultado["caracteristicas"]
                categorias_count[categoria] = get(categorias_count, categoria, 0) + length(features)
            end
        end
    end
    
    resumen["total_features"] = sum(values(categorias_count))
    resumen["features_por_categoria"] = categorias_count
    resumen["categorias"] = collect(keys(categorias_count))
    
    return resumen
end

# ==============================================================================
# MENSAJE DE INICIALIZACIÓN
# ==============================================================================

println("📦 Módulo AnalisisRadiomico.jl cargado")