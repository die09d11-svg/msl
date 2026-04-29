if Threads.nthreads() == 1
    println("⚠️  Julia se inició con 1 solo thread   ⚠️")
    println("   Para habilitar paralelismo en analisis radiomico, reinicia Julia con:")
    println("   julia -t auto server.jl")
    println("   (o especifica número: julia -t 4 server.jl)")
    println("")
end

using HTTP
using JSON3
using Dates

# IMPORTANTE: Intentar cargar NativeFileDialog (opcional)
NATIVE_FILE_DIALOG_AVAILABLE = false
try
    using NativeFileDialog
    global NATIVE_FILE_DIALOG_AVAILABLE = true
    println("✅ NativeFileDialog.jl cargado - Selector de carpetas disponible")
catch e
    println("⚠️  NativeFileDialog.jl no disponible - Solo modo navegador")
    println("   Instalar con: using Pkg; Pkg.add(\"NativeFileDialog\")")
end

# Incluir módulos de procesamiento
include("ProcesamientoImagenes.jl")
include("AnalisisRadiomico.jl")
include("AnalisisEstadistico.jl")

# ==============================================================================
# CONFIGURACIÓN GLOBAL
# ==============================================================================

const PORT = 8000

# Variable global para proyecto actual (CRÍTICA para guardado correcto)
const PROYECTO_ACTUAL = Dict{String, String}(
    "ruta" => "",
    "nombre" => ""
)

# Cache de imágenes cargadas
const LOADED_IMAGES = Dict{String, Any}()

# Modo de operación (julia o python - preparación futura)
const MODO_OPERACION = Ref("julia")

# Inicializar directorio temporal
init_temp_dir()

# ==============================================================================
# FUNCIONES AUXILIARES DE SERVIDOR
# ==============================================================================

"""
Agrega headers CORS a la respuesta
"""
function add_cors_headers(response)
    HTTP.setheader(response, "Access-Control-Allow-Origin" => "*")
    HTTP.setheader(response, "Access-Control-Allow-Methods" => "GET, POST, OPTIONS, DELETE")
    HTTP.setheader(response, "Access-Control-Allow-Headers" => "Content-Type")
    HTTP.setheader(response, "Content-Type" => "application/json")
    return response
end

# ==============================================================================
# FUNCIONES DE GESTIÓN DE PROYECTOS Y CARPETAS
# ==============================================================================

"""
Escanea un directorio recursivamente y retorna estructura JSON jerárquica
"""
function escanear_directorio_recursivo(ruta::String, ruta_base::String="", nivel::Int=0)
    if isempty(ruta_base)
        ruta_base = ruta
    end
    
    nombre = basename(ruta)
    ruta_relativa = replace(ruta, ruta_base * (Sys.iswindows() ? "\\" : "/") => "")
    if isempty(ruta_relativa)
        ruta_relativa = nombre
    end
    
    # Archivo
    if isfile(ruta)
        return Dict(
            "name" => nombre,
            "type" => "file",
            "path" => ruta_relativa,
            "fullPath" => ruta,
            "compatible" => is_compatible_file(nombre)
        )
    end
    
    # Directorio
    children = []
    
    try
        items = readdir(ruta, join=true, sort=true)
        
        for item in items
            item_name = basename(item)
            
            # Ignorar carpetas especiales
            if startswith(item_name, "Resultados_") || 
               item_name in [".git", "node_modules", ".vscode", "__pycache__"]
                continue
            end
            
            child = escanear_directorio_recursivo(item, ruta_base, nivel + 1)
            push!(children, child)
        end
    catch e
        println("⚠️  Error escaneando $ruta: $e")
    end
    
    return Dict(
        "name" => nombre,
        "type" => "folder",
        "path" => ruta_relativa,
        "fullPath" => ruta,
        "children" => children
    )
end

"""
Cuenta archivos en estructura recursiva
"""
function contar_archivos(estructura::Dict)
    if estructura["type"] == "file"
        return 1
    end
    
    count = 0
    if haskey(estructura, "children")
        for child in estructura["children"]
            count += contar_archivos(child)
        end
    end
    
    return count
end

"""
Cuenta carpetas en estructura recursiva
"""
function contar_carpetas(estructura::Dict)
    if estructura["type"] == "file"
        return 0
    end
    
    count = 1  # Contar esta carpeta
    if haskey(estructura, "children")
        for child in estructura["children"]
            if child["type"] == "folder"
                count += contar_carpetas(child)
            end
        end
    end
    
    return count
end

"""
Determina la ruta de guardado según el contexto del proyecto actual
REGLA: Carpeta hermana con prefijo "Resultados_"
"""
function determinar_ruta_guardado(nombre_proyecto::String="")
    if !isempty(PROYECTO_ACTUAL["ruta"]) && isdir(PROYECTO_ACTUAL["ruta"])
        # Tenemos ruta real del proyecto
        ruta_padre = dirname(PROYECTO_ACTUAL["ruta"])
        nombre = isempty(nombre_proyecto) ? PROYECTO_ACTUAL["nombre"] : nombre_proyecto
        
        # Crear carpeta hermana con prefijo "Resultados_"
        ruta_resultados = joinpath(ruta_padre, "Resultados_$nombre")
        
        # Crear subcarpetas si no existen
        mkpath(joinpath(ruta_resultados, "radiomics"))
        mkpath(joinpath(ruta_resultados, "imagenes"))
        mkpath(joinpath(ruta_resultados, "estadisticas"))
        
        println("Ruta de guardado: $ruta_resultados")
        return ruta_resultados
    else
        # Fallback a Escritorio
        base = Sys.iswindows() ? joinpath(homedir(), "Desktop") : homedir()
        ruta_resultados = joinpath(base, "Resultados")
        mkpath(ruta_resultados)
        println("⚠️  Sin proyecto activo, usando fallback: $ruta_resultados")
        return ruta_resultados
    end
end

"""
Guarda resultados de análisis estadístico en Excel
"""
function guardar_resultados_estadisticos_excel(result::Dict, base_resultados::String)
    try
        dir_resultados = joinpath(base_resultados, "estadisticas")
        mkpath(dir_resultados)
        
        timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
        nombre_archivo = "estadisticas_$(timestamp).xlsx"
        ruta_completa = joinpath(dir_resultados, nombre_archivo)
        
        println("📊 Generando archivo Excel: $nombre_archivo")
        
        # Usar función del módulo para preparar datos
        filas = preparar_datos_para_excel(result)
        
        XLSX.openxlsx(ruta_completa, mode="w") do xf
            # HOJA 1: RESULTADOS
            sheet_resultados = xf[1]
            XLSX.rename!(sheet_resultados, "Resultados")
            
            # Escribir datos fila por fila
            for (idx, fila) in enumerate(filas)
                for (col_idx, valor) in enumerate(fila)
                    sheet_resultados[XLSX.CellRef(idx, col_idx)] = valor
                end
            end
            
            # HOJA 2: RESUMEN
            XLSX.addsheet!(xf, "Resumen")
            sheet_resumen = xf["Resumen"]
            
            sheet_resumen["A1"] = "ANÁLISIS ESTADÍSTICO - RESUMEN"
            sheet_resumen["A2"] = "Generado: $(Dates.format(now(), "dd/mm/yyyy HH:MM:SS"))"
            
            row = 4
            sheet_resumen["A$(row)"] = "Métrica"
            sheet_resumen["B$(row)"] = "Valor"
            
            row += 1
            sheet_resumen["A$(row)"] = "Tiempo total (segundos)"
            sheet_resumen["B$(row)"] = get(result, "tiempo_analisis", 0.0)
            
            row += 1
            sheet_resumen["A$(row)"] = "Número de grupos"
            sheet_resumen["B$(row)"] = get(result, "num_grupos", 0)
            
            row += 1
            sheet_resumen["A$(row)"] = "Tipo de distribución"
            sheet_resumen["B$(row)"] = get(result["parametricidad"], "es_parametrico", false) ? "Paramétrica" : "No Paramétrica"
            
            row += 2
            sheet_resumen["A$(row)"] = "GRUPOS ANALIZADOS"
            
            if haskey(result, "nombres_grupos")
                for grupo in result["nombres_grupos"]
                    row += 1
                    sheet_resumen["A$(row)"] = grupo
                end
            end
            
            # HOJA 3: INTERPRETACIÓN
            XLSX.addsheet!(xf, "Interpretacion")
            sheet_interp = xf["Interpretacion"]
            
            sheet_interp["A1"] = "INTERPRETACIÓN DE RESULTADOS"
            sheet_interp["A2"] = "="^50
            
            interpretacion = generar_resumen_interpretativo(result)
            lineas = split(interpretacion, "\n")
            
            for (idx, linea) in enumerate(lineas)
                sheet_interp["A$(idx+3)"] = linea
            end
            
            # Ajustar anchos de columna
            XLSX.setcolwidth!(sheet_resultados, "A:A", 35)
            XLSX.setcolwidth!(sheet_resultados, "B:B", 25)
            XLSX.setcolwidth!(sheet_resultados, "C:C", 15)
            XLSX.setcolwidth!(sheet_resultados, "D:D", 40)
            
            XLSX.setcolwidth!(sheet_resumen, "A:B", 30)
            XLSX.setcolwidth!(sheet_interp, "A:A", 80)
        end
        
        println("✅ Archivo Excel guardado: $ruta_completa")
        return ruta_completa
        
    catch e
        println("❌ Error guardando Excel: $e")
        println(stacktrace(catch_backtrace()))
        throw(e)
    end
end

# ==============================================================================
# ROUTER PRINCIPAL
# ==============================================================================

function handle_request(req::HTTP.Request)
    # Manejar preflight CORS
    if req.method == "OPTIONS"
        response = HTTP.Response(200, "")
        return add_cors_headers(response)
    end
    
    uri = HTTP.URI(req.target)
    path = uri.path
    
    try
        # ======================================================================
        # RAÍZ - Información del servidor
        # ======================================================================
        if path == "/"
            data = Dict(
                "server" => "MSL Process Backend v2.0",
                "status" => "running",
                "native_file_dialog" => NATIVE_FILE_DIALOG_AVAILABLE,
                "proyecto_actual" => PROYECTO_ACTUAL,
                "modo_operacion" => MODO_OPERACION[],
                "endpoints" => [
                    "/api/test",
                    "/api/info",
                    "/api/seleccionar-carpeta-local",
                    "/api/crear-proyecto",
                    "/api/agregar-grupos",
                    "/api/agregar-archivos",
                    "/api/cambiar-modo",
                    "/api/analisis-estadistico",
                    "/api/upload-file",
                    "/api/check-file",
                    "/api/load-image",
                    "/api/get-slice",
                    "/api/guardar-imagen",
                    "/api/analisis-radiomico",
                    "/api/limpiar-cache"
                ]
            )
            response = HTTP.Response(200, JSON3.write(data))
            return add_cors_headers(response)
        
        # ======================================================================
        # TEST - Verificar servidor
        # ======================================================================
        elseif path == "/api/test"
            data = Dict(
                "status" => "ok",
                "message" => "Servidor funcionando correctamente",
                "timestamp" => string(now())
            )
            response = HTTP.Response(200, JSON3.write(data))
            return add_cors_headers(response)
        
        # ======================================================================
        # INFO - Información del sistema
        # ======================================================================
        elseif path == "/api/info"
            data = Dict(
                "julia_version" => string(VERSION),
                "threads" => Threads.nthreads(),
                "loaded_images" => length(LOADED_IMAGES),
                "temp_dir" => TEMP_DIR,
                "proyecto_actual" => PROYECTO_ACTUAL,
                "native_file_dialog" => NATIVE_FILE_DIALOG_AVAILABLE,
                "modo_operacion" => MODO_OPERACION[]
            )
            response = HTTP.Response(200, JSON3.write(data))
            return add_cors_headers(response)
        
        # ======================================================================
        # SELECCIONAR-CARPETA-LOCAL - Método GUI nativo
        # ======================================================================
        elseif path == "/api/seleccionar-carpeta-local" && req.method == "POST"
            if !NATIVE_FILE_DIALOG_AVAILABLE
                result = Dict(
                    "success" => false,
                    "error" => "NativeFileDialog no disponible",
                    "usar_fallback" => true
                )
                response = HTTP.Response(501, JSON3.write(result))
                return add_cors_headers(response)
            end
            
            try
                folder_path = pick_folder()
                
                if !isnothing(folder_path) && isdir(folder_path)
                    nombre_proyecto = basename(folder_path)
                    PROYECTO_ACTUAL["ruta"] = folder_path
                    PROYECTO_ACTUAL["nombre"] = nombre_proyecto
                    
                    println("Proyecto seleccionado: $folder_path")
                    
                    # Escanear estructura de carpetas
                    estructura = escanear_directorio_recursivo(folder_path)
                    
                    result = Dict(
                        "success" => true,
                        "ruta_proyecto" => folder_path,
                        "nombre_proyecto" => nombre_proyecto,
                        "estructura" => estructura,
                        "num_archivos" => contar_archivos(estructura),
                        "num_carpetas" => contar_carpetas(estructura),
                        "metodo" => "local"
                    )
                    
                    println("✅ Estructura escaneada: $(result["num_archivos"]) archivos, $(result["num_carpetas"]) carpetas")
                else
                    result = Dict("success" => false, "error" => "Selección cancelada")
                end
            catch e
                println("❌ Error en pick_folder: $e")
                result = Dict(
                    "success" => false,
                    "error" => "Error abriendo selector: $(string(e))",
                    "usar_fallback" => true
                )
            end
            
            response = HTTP.Response(result["success"] ? 200 : 500, JSON3.write(result))
            return add_cors_headers(response)
        
        # ======================================================================
        # CREAR-PROYECTO - Crear proyecto con grupos
        # ======================================================================
        elseif path == "/api/crear-proyecto" && req.method == "POST"
            body = String(req.body)
            request_data = JSON3.read(body)
            
            ruta_base = get(request_data, "ruta_base", "")
            nombre_proyecto = get(request_data, "nombre_proyecto", "Nuevo_Proyecto")
            num_grupos = get(request_data, "num_grupos", 0)
            nombres_grupos = get(request_data, "nombres_grupos", String[])
            
            # Si ruta_base está vacía, usar Escritorio
            if isempty(ruta_base)
                ruta_base = Sys.iswindows() ? joinpath(homedir(), "Desktop") : homedir()
            end
            
            # Crear carpeta del proyecto
            ruta_proyecto = joinpath(ruta_base, nombre_proyecto)
            
            if isdir(ruta_proyecto)
                result = Dict(
                    "success" => false,
                    "error" => "El proyecto ya existe en esa ubicación"
                )
            else
                try
                    mkpath(ruta_proyecto)
                    println("Proyecto creado: $ruta_proyecto")
                    
                    # Crear grupos
                    carpetas_creadas = String[]
                    if num_grupos > 0
                        for i in 1:num_grupos
                            nombre_grupo = if !isempty(nombres_grupos) && i <= length(nombres_grupos)
                                nombres_grupos[i]
                            else
                                "Grupo_$i"
                            end
                            
                            ruta_grupo = joinpath(ruta_proyecto, nombre_grupo)
                            mkpath(ruta_grupo)
                            push!(carpetas_creadas, nombre_grupo)
                            println("  Grupo creado: $nombre_grupo")
                        end
                    end
                    
                    # Crear carpeta de resultados (hermana)
                    ruta_resultados = joinpath(ruta_base, "Resultados_$nombre_proyecto")
                    mkpath(joinpath(ruta_resultados, "radiomics"))
                    mkpath(joinpath(ruta_resultados, "imagenes"))
                    mkpath(joinpath(ruta_resultados, "estadisticas"))
                    println(" Carpeta de resultados: $ruta_resultados")
                    
                    # Registrar como proyecto actual
                    PROYECTO_ACTUAL["ruta"] = ruta_proyecto
                    PROYECTO_ACTUAL["nombre"] = nombre_proyecto
                    
                    # Escanear estructura
                    estructura = escanear_directorio_recursivo(ruta_proyecto)
                    
                    result = Dict(
                        "success" => true,
                        "ruta_proyecto" => ruta_proyecto,
                        "ruta_resultados" => ruta_resultados,
                        "carpetas_creadas" => carpetas_creadas,
                        "estructura" => estructura,
                        "message" => "Proyecto creado exitosamente"
                    )
                    
                    println("✅ Proyecto registrado como actual")
                    
                catch e
                    println("❌ Error creando proyecto: $e")
                    result = Dict(
                        "success" => false,
                        "error" => string(e)
                    )
                end
            end
            
            response = HTTP.Response(result["success"] ? 200 : 400, JSON3.write(result))
            return add_cors_headers(response)
        
        # ======================================================================
        # AGREGAR-GRUPOS - Agregar grupos a proyecto existente
        # ======================================================================
        elseif path == "/api/agregar-grupos" && req.method == "POST"
            body = String(req.body)
            request_data = JSON3.read(body)
            
            ruta_proyecto = get(request_data, "ruta_proyecto", PROYECTO_ACTUAL["ruta"])
            num_grupos = get(request_data, "num_grupos", 1)
            prefijo = get(request_data, "prefijo", "Grupo")
            
            if isempty(ruta_proyecto) || !isdir(ruta_proyecto)
                result = Dict(
                    "success" => false,
                    "error" => "Ruta de proyecto inválida"
                )
            else
                try
                    # Obtener grupos existentes
                    grupos_existentes = filter(isdir, 
                        [joinpath(ruta_proyecto, item) for item in readdir(ruta_proyecto)])
                    num_actual = length(grupos_existentes)
                    
                    carpetas_creadas = String[]
                    for i in 1:num_grupos
                        nombre_grupo = "$(prefijo)_$(num_actual + i)"
                        ruta_grupo = joinpath(ruta_proyecto, nombre_grupo)
                        mkpath(ruta_grupo)
                        push!(carpetas_creadas, nombre_grupo)
                        println("  Grupo agregado: $nombre_grupo")
                    end
                    
                    # Re-escanear estructura
                    estructura = escanear_directorio_recursivo(ruta_proyecto)
                    
                    result = Dict(
                        "success" => true,
                        "carpetas_creadas" => carpetas_creadas,
                        "estructura" => estructura
                    )
                    
                    println("✅ $(length(carpetas_creadas)) grupos agregados")
                    
                catch e
                    println("❌ Error agregando grupos: $e")
                    result = Dict(
                        "success" => false,
                        "error" => string(e)
                    )
                end
            end
            
            response = HTTP.Response(result["success"] ? 200 : 400, JSON3.write(result))
            return add_cors_headers(response)
        
        # ======================================================================
        # AGREGAR-ARCHIVOS - Copiar archivos a carpeta del proyecto
        # ======================================================================
        elseif path == "/api/agregar-archivos" && req.method == "POST"
            body = String(req.body)
            request_data = JSON3.read(body)
            
            ruta_proyecto = get(request_data, "ruta_proyecto", "")
            carpeta_destino = get(request_data, "carpeta_destino", "")
            nombre_base = get(request_data, "nombre_base", "Archivo")
            archivos = get(request_data, "archivos", [])
            
            if isempty(ruta_proyecto) || !isdir(ruta_proyecto)
                result = Dict(
                    "success" => false,
                    "error" => "Ruta de proyecto inválida"
                )
                response = HTTP.Response(400, JSON3.write(result))
                return add_cors_headers(response)
            end
            
            ruta_carpeta_destino = joinpath(ruta_proyecto, carpeta_destino)
            
            if !isdir(ruta_carpeta_destino)
                result = Dict(
                    "success" => false,
                    "error" => "Carpeta destino no existe: $carpeta_destino"
                )
                response = HTTP.Response(400, JSON3.write(result))
                return add_cors_headers(response)
            end
            
            try
                archivos_agregados = String[]
                
                for (idx, archivo_info) in enumerate(archivos)
                    data_base64 = get(archivo_info, "data", "")
                    extension = get(archivo_info, "extension", "dat")
                    
                    # Decodificar Base64
                    file_data = base64decode(data_base64)
                    
                    # Generar nombre: NombreBase_1.ext, NombreBase_2.ext, etc.
                    nombre_archivo = "$(nombre_base)_$(idx).$(extension)"
                    ruta_completa = joinpath(ruta_carpeta_destino, nombre_archivo)
                    
                    # Guardar archivo físicamente
                    write(ruta_completa, file_data)
                    push!(archivos_agregados, nombre_archivo)
                    
                    println("  📄 Archivo copiado: $nombre_archivo")
                end
                
                # Re-escanear estructura
                estructura = escanear_directorio_recursivo(ruta_proyecto)
                
                result = Dict(
                    "success" => true,
                    "archivos_agregados" => archivos_agregados,
                    "estructura" => estructura,
                    "message" => "$(length(archivos_agregados)) archivo(s) agregado(s)"
                )
                
                println("✅ $(length(archivos_agregados)) archivos agregados a $carpeta_destino")
                
            catch e
                println("❌ Error agregando archivos: $e")
                result = Dict(
                    "success" => false,
                    "error" => string(e)
                )
            end
            
            response = HTTP.Response(result["success"] ? 200 : 500, JSON3.write(result))
            return add_cors_headers(response)
        
        # ======================================================================
        # CAMBIAR-MODO - Cambiar entre Julia/Python (Util para agregar IA)
        # ======================================================================
        elseif path == "/api/cambiar-modo" && req.method == "POST"
            body = String(req.body)
            request_data = JSON3.read(body)
            
            nuevo_modo = get(request_data, "modo", "julia")
            
            if nuevo_modo in ["julia", "python"]
                MODO_OPERACION[] = nuevo_modo
                println("🔄 Modo cambiado a: $nuevo_modo")
                
                result = Dict(
                    "success" => true,
                    "modo_actual" => nuevo_modo,
                    "message" => "Modo de operación actualizado"
                )
            else
                result = Dict(
                    "success" => false,
                    "error" => "Modo inválido. Use 'julia' o 'python'"
                )
            end
            
            response = HTTP.Response(result["success"] ? 200 : 400, JSON3.write(result))
            return add_cors_headers(response)
        
        # ======================================================================
        # ANALISIS-ESTADISTICO - Análisis estadístico completo
        # ======================================================================
        elseif path == "/api/analisis-estadistico" && req.method == "POST"
            body = String(req.body)
            request_data = JSON3.read(body)
            
            grupos = get(request_data, "grupos", Dict())
            pruebas = get(request_data, "pruebas", String[])
            comparar_por_archivos = get(request_data, "comparar_por_archivos", true)
            tipo_datos = get(request_data, "tipo_datos", "imagenes")
            
            if isempty(grupos) || length(grupos) < 2
                result = Dict(
                    "success" => false,
                    "error" => "Se necesitan al menos 2 grupos para análisis estadístico"
                )
                response = HTTP.Response(400, JSON3.write(result))
                return add_cors_headers(response)
            end
            
            println("\n📊 Iniciando análisis estadístico...")
            println("   Grupos: $(length(grupos))")
            println("   Pruebas seleccionadas: $(length(pruebas))")
            println("   Tipo de datos: $tipo_datos")
            
            # Llamar al módulo de estadísticas
            result = analizar_estadistico(grupos, pruebas, comparar_por_archivos, tipo_datos)
            
            # Guardar resultados en Excel
            if result["success"]
                try
                    ruta_resultados = determinar_ruta_guardado()
                    ruta_excel = guardar_resultados_estadisticos_excel(result, ruta_resultados)
                    result["ruta_excel"] = ruta_excel
                    println("📊 Excel guardado: $ruta_excel")
                catch e
                    println("⚠️  Error guardando Excel: $e")
                end
            end
            
            response = HTTP.Response(result["success"] ? 200 : 500, JSON3.write(result))
            return add_cors_headers(response)
        
        # ======================================================================
        # UPLOAD-FILE - Subir archivo al servidor
        # ======================================================================
        elseif path == "/api/upload-file" && req.method == "POST"
            body = String(req.body)
            request_data = JSON3.read(body)
            
            filename = get(request_data, "filename", "")
            file_data_base64 = get(request_data, "data", "")
            
            if isempty(filename) || isempty(file_data_base64)
                result = Dict(
                    "success" => false,
                    "error" => "Faltan parámetros: filename y data"
                )
                response = HTTP.Response(400, JSON3.write(result))
                return add_cors_headers(response)
            end
            
            result = guardar_archivo_temporal(filename, file_data_base64)
            
            response = HTTP.Response(result["success"] ? 200 : 500, JSON3.write(result))
            return add_cors_headers(response)
        
        # ======================================================================
        # CHECK-FILE - Verificar compatibilidad
        # ======================================================================
        elseif path == "/api/check-file" && req.method == "POST"
            body = String(req.body)
            request_data = JSON3.read(body)
            
            filename = get(request_data, "filename", "")
            compatible = is_compatible_file(filename)
            
            result = Dict(
                "filename" => filename,
                "compatible" => compatible,
                "type" => compatible ? "medical" : "unsupported"
            )
            
            response = HTTP.Response(200, JSON3.write(result))
            return add_cors_headers(response)
        
        # ======================================================================
        # LOAD-IMAGE - Cargar imagen en memoria
        # ======================================================================
        elseif path == "/api/load-image" && req.method == "POST"
            body = String(req.body)
            request_data = JSON3.read(body)
            
            filename = get(request_data, "filename", "")
            filepath = joinpath(TEMP_DIR, filename)
            
            if !isfile(filepath)
                result = Dict(
                    "success" => false,
                    "error" => "Archivo no encontrado",
                    "searched_path" => filepath
                )
                response = HTTP.Response(404, JSON3.write(result))
                return add_cors_headers(response)
            end
            
            img_data = process_medical_image(filepath)
            
            if img_data["success"]
                LOADED_IMAGES[filename] = img_data
                
                result = Dict(
                    "success" => true,
                    "filename" => filename,
                    "type" => img_data["type"],
                    "dimensions" => img_data["dimensions"],
                    "header" => img_data["header"]
                )
            else
                result = img_data
            end
            
            response = HTTP.Response(result["success"] ? 200 : 400, JSON3.write(result))
            return add_cors_headers(response)
        
        # ======================================================================
        # GET-SLICE - Obtener corte específico
        # ======================================================================
        elseif path == "/api/get-slice" && req.method == "POST"
            body = String(req.body)
            request_data = JSON3.read(body)
            
            filename = get(request_data, "filename", "")
            orientation = get(request_data, "orientation", "axial")
            slice_num = get(request_data, "slice", 1)
            
            if !haskey(LOADED_IMAGES, filename)
                result = Dict(
                    "success" => false,
                    "error" => "Imagen no cargada"
                )
                response = HTTP.Response(404, JSON3.write(result))
                return add_cors_headers(response)
            end
            
            img_data = LOADED_IMAGES[filename]
            data_3d = img_data["data"]
            
            slice_matrix = extract_slice(data_3d, orientation, slice_num)
            img_base64 = matrix_to_base64_png(slice_matrix)
            
            result = Dict(
                "success" => true,
                "filename" => filename,
                "orientation" => orientation,
                "slice" => slice_num,
                "max_slices" => size(data_3d)[orientation == "sagittal" ? 1 : 
                                              orientation == "coronal" ? 2 : 3],
                "image" => img_base64
            )
            
            response = HTTP.Response(200, JSON3.write(result))
            return add_cors_headers(response)
        
        # ======================================================================
        # GUARDAR-IMAGEN - Guardar imagen en carpeta de resultados
        # ======================================================================
        elseif path == "/api/guardar-imagen" && req.method == "POST"
            body = String(req.body)
            request_data = JSON3.read(body)
            
            nombre_archivo = get(request_data, "nombre_archivo", "")
            imagen_base64 = get(request_data, "imagen_base64", "")
            
            if isempty(nombre_archivo) || isempty(imagen_base64)
                result = Dict(
                    "success" => false,
                    "error" => "Faltan parámetros"
                )
                response = HTTP.Response(400, JSON3.write(result))
                return add_cors_headers(response)
            end
            
            # USAR NUEVA FUNCIÓN DE GUARDADO
            ruta_resultados = determinar_ruta_guardado()
            carpeta_imagenes = joinpath(ruta_resultados, "imagenes")
            
            try
                img_data = base64decode(imagen_base64)
                ruta_completa = joinpath(carpeta_imagenes, nombre_archivo)
                write(ruta_completa, img_data)
                
                result = Dict(
                    "success" => true,
                    "ruta_completa" => ruta_completa,
                    "carpeta_resultados" => ruta_resultados,
                    "message" => "Imagen guardada exitosamente"
                )
                
                println("✅ Imagen guardada: $ruta_completa")
            catch e
                result = Dict(
                    "success" => false,
                    "error" => string(e)
                )
            end
            
            response = HTTP.Response(result["success"] ? 200 : 500, JSON3.write(result))
            return add_cors_headers(response)
        
        # ======================================================================
        # ANALISIS-RADIOMICO - Análisis radiómico de archivos
        # ======================================================================
        elseif path == "/api/analisis-radiomico" && req.method == "POST"
            body = String(req.body)
            request_data = JSON3.read(body)
            
            archivos = get(request_data, "archivos", String[])
            modo_paralelo = get(request_data, "modo_paralelo", false)
            
            if isempty(archivos)
                result = Dict(
                    "success" => false,
                    "error" => "No se proporcionaron archivos"
                )
                response = HTTP.Response(400, JSON3.write(result))
                return add_cors_headers(response)
            end
            
            # Convertir a rutas completas
            rutas_completas = [joinpath(TEMP_DIR, archivo) for archivo in archivos]
            
            # Verificar existencia
            archivos_faltantes = [archivo for (archivo, ruta) in zip(archivos, rutas_completas) if !isfile(ruta)]
            if !isempty(archivos_faltantes)
                result = Dict(
                    "success" => false,
                    "error" => "Archivos no encontrados: $(join(archivos_faltantes, ", "))"
                )
                response = HTTP.Response(404, JSON3.write(result))
                return add_cors_headers(response)
            end
            
            println("\n🔬 Iniciando análisis radiómico...")
            println("   Archivos: $(length(archivos))")
            println("   Modo: $(modo_paralelo ? "PARALELO" : "LINEAL")")
            
            # Llamar módulo de radiómca
            result = analizar_radiomico(rutas_completas, modo_paralelo)
            
            if result["success"]
                println("✅ Análisis completado")
                
                # Guardar Excel en carpeta de resultados
                try
                    ruta_resultados = determinar_ruta_guardado()
                    ruta_excel = guardar_resultados_radiomicos_excel(result, ruta_resultados)
                    result["ruta_excel"] = ruta_excel
                    println("📊 Excel guardado: $ruta_excel")
                catch e
                    println("⚠️  Error guardando Excel: $e")
                end
            end
            
            response = HTTP.Response(result["success"] ? 200 : 500, JSON3.write(result))
            return add_cors_headers(response)
        
        # ======================================================================
        # LIMPIAR-CACHE - Limpiar archivos temporales
        # ======================================================================
        elseif path == "/api/limpiar-cache" && req.method == "DELETE"
            result = limpiar_cache()
            empty!(LOADED_IMAGES)
            result["loaded_images_cleared"] = true
            
            response = HTTP.Response(200, JSON3.write(result))
            return add_cors_headers(response)
        
        # ======================================================================
        # RUTA NO ENCONTRADA
        # ======================================================================
        else
            error_data = Dict("error" => "Ruta no encontrada", "path" => path)
            response = HTTP.Response(404, JSON3.write(error_data))
            return add_cors_headers(response)
        end
        
    catch e
        println("❌ Error interno: ", e)
        println(stacktrace(catch_backtrace()))
        error_data = Dict(
            "error" => "Error interno del servidor",
            "message" => string(e)
        )
        response = HTTP.Response(500, JSON3.write(error_data))
        return add_cors_headers(response)
    end
end

# ==============================================================================
# INICIAR SERVIDOR
# ==============================================================================

println("╔═══════════════════════════════════════════════════════════╗")
println("        MSL Process Backend v2.0 - Arquitectura Jerárquica")
println("╠═══════════════════════════════════════════════════════════╣")
println("    Puerto: http://localhost:$PORT")
println("    Temp: $TEMP_DIR")
println("    NativeFileDialog: $(NATIVE_FILE_DIALOG_AVAILABLE ? "✅ Disponible" : "❌ No disponible")")
println("    Modo: $(MODO_OPERACION[])")
println("    Threads: $(Threads.nthreads())")
println("╚═══════════════════════════════════════════════════════════╝")
println("Presiona Ctrl+C para detener\n")

# ==============================================================================
# CONFIGURACIÓN DE RED
# ==============================================================================

# Detectar modo de operación desde variable de entorno
const SERVER_MODE = get(ENV, "MSL_SERVER_MODE", "desktop")
const HOST = SERVER_MODE == "server" ? "0.0.0.0" : "127.0.0.1"

if SERVER_MODE == "server"
    println("🌐 MODO SERVIDOR - Escuchando en toda la red (0.0.0.0:$PORT)")
    println("   Acceso desde otras PCs: http://[IP-DEL-SERVIDOR]:$PORT")
    println("   ⚠️  Asegúrate de configurar el firewall correctamente")
else
    println("🖥️  MODO ESCRITORIO - Solo local (127.0.0.1:$PORT)")
end

HTTP.serve(handle_request, HOST, PORT)