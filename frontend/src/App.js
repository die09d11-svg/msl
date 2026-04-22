import React, { useState, useRef, useEffect } from 'react';
import { FolderOpen, FolderPlus, ArrowLeft, Activity, Upload, Plus } from 'lucide-react';

export default function LabMedicoApp() {
  const [currentView, setCurrentView] = useState('home');
  const [projectStructure, setProjectStructure] = useState(null);
  const [juliaStatus, setJuliaStatus] = useState('checking');
  const [juliaInfo, setJuliaInfo] = useState(null);
  const [activeTab, setActiveTab] = useState('visualization');
  const [selectedFile, setSelectedFile] = useState(null);
  const [imageLoaded, setImageLoaded] = useState(false);
  const [imageDimensions, setImageDimensions] = useState(null);
  const [slices, setSlices] = useState({
    sagittal: { num: 1, image: null },
    coronal: { num: 1, image: null },
    axial: { num: 1, image: null }
  });
  const [projectPath, setProjectPath] = useState('');
  
  // Estados para Radiómica y selección
  const [multipleFilesMode, setMultipleFilesMode] = useState(true);
  const [parallelMode, setParallelMode] = useState(false);
  const [radiomicsRunning, setRadiomicsRunning] = useState(false);
  const [radiomicsResults, setRadiomicsResults] = useState(null);
  const [selectedFiles, setSelectedFiles] = useState([]);
  const [selectedFolders, setSelectedFolders] = useState([]);
  const [radiomicsProgress, setRadiomicsProgress] = useState(0);
  
  // Estados para Estadísticas
  const [statisticsRunning, setStatisticsRunning] = useState(false);
  const [statisticsResults, setStatisticsResults] = useState(null);
  const [compareByFiles, setCompareByFiles] = useState(true); // Para Excel: true = entre archivos, false = entre carpetas
  const [selectedTests, setSelectedTests] = useState({
    tTest: true,
    anova: true,
    correlation: true,
    multipleComparisons: true,
    nonParametric: true,
    fisherVariance: true,
    correlationMatrix: true,
    zVariance: true
  });
  
  // Estado para splash screen
  const [loadingFiles, setLoadingFiles] = useState(false);
  const [loadingMessage, setLoadingMessage] = useState('');
  
  const [expandedResult, setExpandedResult] = useState(null);
  
  const fileInputRef = useRef(null);
  const addFilesInputRef = useRef(null);
  const progressIntervalRef = useRef(null);
  // Detectar si estamos en modo servidor o escritorio
  const JULIA_API = process.env.REACT_APP_API_URL || "http://localhost:8000";
// Debug en consola
console.log('🔌 Backend Julia:', JULIA_API);

  useEffect(() => {
    checkJuliaConnection();
  }, []);

  // Limpiar interval de progreso al desmontar
  useEffect(() => {
    return () => {
      if (progressIntervalRef.current) {
        clearInterval(progressIntervalRef.current);
      }
    };
  }, []);

  const checkJuliaConnection = async () => {
    try {
      const response = await fetch(`${JULIA_API}/api/test`);
      const data = await response.json();
      
      if (data.status === 'ok') {
        setJuliaStatus('connected');
        const infoResponse = await fetch(`${JULIA_API}/api/info`);
        const infoData = await infoResponse.json();
        setJuliaInfo(infoData);
      }
    } catch (error) {
      console.error('Error conectando con Julia:', error);
      setJuliaStatus('disconnected');
    }
  };

  // ============================================================================
  // GESTIÓN DE PROYECTOS
  // ============================================================================

  const handleOpenProject = async () => {
    // Verificar que Julia esté conectado
    if (juliaStatus !== 'connected') {
      alert('⚠️  El servidor de Julia no está conectado.\n\nPor favor, inicia server.jl primero.');
      return;
    }

    try {
      setLoadingFiles(true);
      setLoadingMessage('Abriendo selector de carpetas...');
      
      const response = await fetch(`${JULIA_API}/api/seleccionar-carpeta-local`, {
        method: 'POST'
      });
      const result = await response.json();
      
      if (result.success) {
        setProjectPath(result.ruta_proyecto);
        setProjectStructure(result.estructura);
        setCurrentView('workspace');
        
        // Subir archivos a TEMP y auto-cargar primera imagen
        const allFiles = extractAllCompatibleFiles(result.estructura);
        if (allFiles.length > 0) {
          setLoadingMessage(`Subiendo ${allFiles.length} archivos al servidor...`);
          
          // Subir todos los archivos a TEMP_DIR
          for (let i = 0; i < allFiles.length; i++) {
            const fileNode = allFiles[i];
            setLoadingMessage(`Subiendo ${i + 1}/${allFiles.length}: ${fileNode.name}`);
            
            // Leer archivo desde disco usando fullPath
            const response = await fetch(fileNode.fullPath);
            const blob = await response.blob();
            const file = new File([blob], fileNode.name);
            await uploadFileToServer(file);
          }
          
          // Auto-cargar primera imagen
          setLoadingMessage('Cargando primera imagen...');
          await autoLoadFirstImage(allFiles[0]);
        }
        
        setLoadingFiles(false);
      } else if (result.usar_fallback) {
        console.log('📁 Usando selector de navegador (fallback)');
        setLoadingFiles(false);
        fileInputRef.current.click();
      } else {
        setLoadingFiles(false);
        alert('❌ Error: ' + result.error);
      }
    } catch (error) {
      console.log('📁 Usando selector de navegador');
      setLoadingFiles(false);
      fileInputRef.current.click();
    }
  };

  const handleFileChange = async (event) => {
    const fileList = Array.from(event.target.files);
    if (fileList.length > 0) {
      setLoadingFiles(true);
      setLoadingMessage('Procesando archivos del navegador...');
      
      const firstFile = fileList[0];
      const pathParts = firstFile.webkitRelativePath.split('/');
      const folderName = pathParts[0];
      
      setLoadingMessage('Construyendo estructura de carpetas...');
      const tree = buildTreeFromFiles(fileList, folderName);
      setProjectStructure(tree);
      
      // Subir todos los archivos a TEMP_DIR
      setLoadingMessage(`Subiendo ${fileList.length} archivos...`);
      for (let i = 0; i < fileList.length; i++) {
        setLoadingMessage(`Subiendo ${i + 1}/${fileList.length}: ${fileList[i].name}`);
        await uploadFileToServer(fileList[i]);
      }
      
      // Detectar ruta absoluta
      try {
        const uploadResult = await uploadFileToServer(firstFile);
        if (uploadResult.success && uploadResult.absolute_path) {
          const absolutePath = uploadResult.absolute_path;
          const projectPathDetected = absolutePath.substring(0, absolutePath.lastIndexOf(firstFile.name) - 1);
          setProjectPath(projectPathDetected);
          console.log('✅ Ruta detectada:', projectPathDetected);
        }
      } catch (error) {
        console.warn('⚠️  No se pudo detectar ruta absoluta:', error);
      }
      
      // Auto-cargar primera imagen
      const firstCompatible = findFirstCompatibleFile(tree);
      if (firstCompatible) {
        setLoadingMessage('Cargando primera imagen...');
        await autoLoadFirstImage(firstCompatible);
      }
      
      setLoadingFiles(false);
      setCurrentView('workspace');
    }
  };

  const buildTreeFromFiles = (fileList, rootName) => {
    const root = {
      name: rootName,
      type: 'folder',
      path: rootName,
      children: []
    };

    const folderMap = { [rootName]: root };

    for (const file of fileList) {
      const parts = file.webkitRelativePath.split('/');
      let currentPath = '';

      for (let i = 0; i < parts.length; i++) {
        const part = parts[i];
        const isFile = i === parts.length - 1;
        currentPath = currentPath ? `${currentPath}/${part}` : part;

        if (!folderMap[currentPath]) {
          const newNode = {
            name: part,
            type: isFile ? 'file' : 'folder',
            path: currentPath,
            ...(isFile && {
              file: file,
              compatible: isCompatibleFile(file.name, activeTab)
            }),
            ...(!isFile && { children: [] })
          };

          const parentPath = currentPath.substring(0, currentPath.lastIndexOf('/'));
          const parent = folderMap[parentPath] || root;
          parent.children.push(newNode);
          folderMap[currentPath] = newNode;
        }
      }
    }

    return root;
  };

  const handleCreateProject = async () => {
    // Verificar que Julia esté conectado
    if (juliaStatus !== 'connected') {
      alert('⚠️  El servidor de Julia no está conectado.\n\nPor favor, inicia server.jl primero.');
      return;
    }

    try {
      setLoadingFiles(true);
      setLoadingMessage('Selecciona dónde crear el proyecto...');
      
      // Primero: seleccionar ubicación
      const locationResponse = await fetch(`${JULIA_API}/api/seleccionar-carpeta-local`, {
        method: 'POST'
      });
      const locationResult = await locationResponse.json();
      
      if (!locationResult.success) {
        setLoadingFiles(false);
        alert('⚠️  Debes seleccionar una ubicación para crear el proyecto');
        return;
      }
      
      const ubicacionBase = locationResult.ruta_proyecto;
      
      const nombreProyecto = prompt('Nombre del nuevo proyecto:');
      if (!nombreProyecto) {
        setLoadingFiles(false);
        return;
      }
      
      const numGruposStr = prompt('¿Cuántos grupos crear? (0 para ninguno):', '2');
      const numGrupos = parseInt(numGruposStr) || 0;

      setLoadingMessage('Creando proyecto...');
      
      const response = await fetch(`${JULIA_API}/api/crear-proyecto`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ruta_base: ubicacionBase,
          nombre_proyecto: nombreProyecto,
          num_grupos: numGrupos
        })
      });
      
      const result = await response.json();
      
      setLoadingFiles(false);
      
      if (result.success) {
        alert(`✅ Proyecto creado:\n${result.ruta_proyecto}\n\nGrupos: ${result.carpetas_creadas.join(', ')}`);
        setProjectPath(result.ruta_proyecto);
        setProjectStructure(result.estructura);
        setCurrentView('workspace');
      } else {
        alert(`❌ Error: ${result.error}`);
      }
    } catch (error) {
      setLoadingFiles(false);
      console.error('Error:', error);
      alert('Error de conexión con el servidor');
    }
  };

  const handleAddGroups = async () => {
    if (!projectPath) {
      alert('⚠️  No hay proyecto activo');
      return;
    }

    const numGruposStr = prompt('¿Cuántos grupos agregar?', '1');
    const numGrupos = parseInt(numGruposStr) || 0;

    if (numGrupos <= 0) return;

    try {
      const response = await fetch(`${JULIA_API}/api/agregar-grupos`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ruta_proyecto: projectPath,
          num_grupos: numGrupos
        })
      });

      const result = await response.json();

      if (result.success) {
        alert(`✅ Grupos agregados:\n${result.carpetas_creadas.join(', ')}`);
        setProjectStructure(result.estructura);
      } else {
        alert(`❌ Error: ${result.error}`);
      }
    } catch (error) {
      console.error('Error:', error);
      alert('Error de conexión con el servidor');
    }
  };

  const handleAddFiles = () => {
    if (!projectPath) {
      alert('⚠️  Primero debes abrir o crear un proyecto');
      return;
    }
    addFilesInputRef.current.click();
  };

  const handleAddFilesChange = async (event) => {
    const fileList = Array.from(event.target.files);
    if (fileList.length === 0) return;

    const carpetaDestino = prompt('¿A qué carpeta agregar los archivos? (escribe el nombre exacto)');
    if (!carpetaDestino) return;

    const nombreBase = prompt('Nombre base para los archivos:', 'Archivo');
    if (!nombreBase) return;

    try {
      setLoadingFiles(true);
      setLoadingMessage('Agregando archivos al proyecto...');

      const response = await fetch(`${JULIA_API}/api/agregar-archivos`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ruta_proyecto: projectPath,
          carpeta_destino: carpetaDestino,
          nombre_base: nombreBase,
          num_archivos: fileList.length,
          archivos: await Promise.all(fileList.map(async (file, idx) => ({
            data: await fileToBase64(file),
            extension: (() => {
  	    	const name = file.name.toLowerCase();
  	    	if (name.endsWith('.nii.gz')) return 'nii.gz';
  		if (name.endsWith('.nii')) return 'nii';
  		if (name.endsWith('.dcm')) return 'dcm';
  		if (name.endsWith('.dicom')) return 'dicom';
  		return file.name.split('.').pop();
		})()
          })))
        })
      });

      const result = await response.json();

      if (result.success) {
        alert(`✅ ${result.archivos_agregados.length} archivos agregados:\n${result.archivos_agregados.join(', ')}`);
        
        // Re-escanear estructura
        setProjectStructure(result.estructura);
        
        // 🔥 CRÍTICO: Subir archivos renombrados a TEMP_DIR
        setLoadingMessage('Sincronizando archivos con servidor...');
        
        for (let i = 0; i < result.archivos_agregados.length; i++) {
          const nombreArchivo = result.archivos_agregados[i]; // "Base_1.nii.gz"
          const archivoOriginal = fileList[i]; // File object original
          
          setLoadingMessage(`Subiendo ${i + 1}/${result.archivos_agregados.length}: ${nombreArchivo}`);
          
          // Crear File con nombre renombrado para que Julia lo reconozca
          const archivoRenombrado = new File([archivoOriginal], nombreArchivo, { 
            type: archivoOriginal.type 
          });
          
          // Subir a TEMP_DIR para que Julia pueda procesarlo
          await uploadFileToServer(archivoRenombrado);
        }
        
        console.log(`✅ ${result.archivos_agregados.length} archivos sincronizados con TEMP_DIR`);
      } else {
        alert(`❌ Error: ${result.error}`);
      }


      setLoadingFiles(false);
    } catch (error) {
      setLoadingFiles(false);
      console.error('Error:', error);
      alert('Error de conexión');
    }
  };

  const fileToBase64 = (file) => {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result.split(',')[1]);
      reader.onerror = reject;
      reader.readAsDataURL(file);
    });
  };

  // ============================================================================
  // ÁRBOL DE CARPETAS CON CHECKBOXES
  // ============================================================================

  const isCompatibleFile = (filename, tab = 'visualization') => {
    const lowerName = filename.toLowerCase();
    const isNiftiOrDicom = lowerName.match(/\.(nii|nii\.gz|dcm|dicom|ima)$/);
    const isExcel = lowerName.match(/\.(xlsx|xls)$/);
    
    if (tab === 'statistics') {
      return isNiftiOrDicom || isExcel;
    }
    return isNiftiOrDicom !== null;
  };

  const FolderTree = ({ node, level = 0 }) => {
    const [isExpanded, setIsExpanded] = useState(true);
    const showCheckboxes = activeTab === 'radiomics' || activeTab === 'statistics';

    const handleToggle = () => {
      setIsExpanded(!isExpanded);
    };

    const handleFileClick = async (fileNode) => {
      if (activeTab === 'visualization') {
        setSelectedFile(fileNode);
        await autoLoadFirstImage(fileNode);
      }
    };

    const handleFileCheckbox = (fileNode) => {
      setSelectedFiles(prev => {
        const isSelected = prev.some(f => f.path === fileNode.path);
        if (isSelected) {
          // Al desmarcar archivo, verificar si su carpeta padre debe desmarcarse
          const newFiles = prev.filter(f => f.path !== fileNode.path);
          
          // Encontrar carpeta padre y verificar si todos sus archivos siguen seleccionados
          setSelectedFolders(prevFolders => {
            return prevFolders.filter(folder => {
              // Si el archivo desmarcado está en esta carpeta
              if (fileNode.path.startsWith(folder.path + '/')) {
                const allFilesInFolder = extractAllCompatibleFiles(folder);
                // Verificar si TODOS los demás archivos siguen seleccionados
                const allStillSelected = allFilesInFolder.every(f => 
                  f.path === fileNode.path || newFiles.some(sf => sf.path === f.path)
                );
                // Solo mantener carpeta marcada si TODOS sus archivos siguen seleccionados
                return allStillSelected;
              }
              return true;
            });
          });
          
          return newFiles;
        } else {
          return [...prev, fileNode];
        }
      });
    };

    const handleFolderCheckbox = (folderNode) => {
      const allFiles = extractAllCompatibleFiles(folderNode);
      const allSelected = allFiles.every(f => selectedFiles.some(sf => sf.path === f.path));
      
      if (allSelected) {
        // Desmarcar todos los archivos de esta carpeta
        setSelectedFiles(prev => prev.filter(f => !allFiles.some(af => af.path === f.path)));
        setSelectedFolders(prev => prev.filter(sf => sf.path !== folderNode.path));
      } else {
        // Marcar todos los archivos de esta carpeta
        setSelectedFiles(prev => {
          const newFiles = allFiles.filter(f => !prev.some(pf => pf.path === f.path));
          return [...prev, ...newFiles];
        });
        setSelectedFolders(prev => {
          if (!prev.some(sf => sf.path === folderNode.path)) {
            return [...prev, folderNode];
          }
          return prev;
        });
      }
    };

    const isFileSelected = node.type === 'file' && selectedFiles.some(f => f.path === node.path);
    const isFolderSelected = node.type === 'folder' && (() => {
      // Una carpeta está "seleccionada" visualmente solo si TODOS sus archivos compatibles están seleccionados
      const allFilesInFolder = extractAllCompatibleFiles(node);
      if (allFilesInFolder.length === 0) return false;
      return allFilesInFolder.every(f => selectedFiles.some(sf => sf.path === f.path));
    })();
    const isCurrentFile = node.type === 'file' && selectedFile?.path === node.path;

    if (node.type === 'file') {
      const compatible = isCompatibleFile(node.name, activeTab);
      
      return (
        <div 
          className={`flex items-center gap-2 py-1 px-2 rounded hover:bg-gray-100 cursor-pointer ${
            isCurrentFile ? 'bg-blue-100 text-blue-700 font-medium' : ''
          }`}
          style={{ paddingLeft: `${level * 20 + 20}px` }}>
          {showCheckboxes && (
            <input
              type="checkbox"
              checked={isFileSelected}
              onChange={() => handleFileCheckbox(node)}
              disabled={!compatible}
              onClick={(e) => e.stopPropagation()}
              className="w-4 h-4 text-blue-600"
            />
          )}
          <div className="flex items-center gap-2 flex-1" onClick={() => handleFileClick(node)}>
            {compatible ? (
              <span className="text-blue-600">📄</span>
            ) : (
              <span className="text-red-500">❌</span>
            )}
            <span className={`text-sm truncate ${!compatible ? 'text-gray-400 line-through' : ''}`}>
              {node.name}
            </span>
          </div>
        </div>
      );
    }

    return (
      <div>
        <div 
          className={`flex items-center gap-2 py-1 px-2 rounded hover:bg-gray-100 ${
            isFolderSelected ? 'bg-blue-50' : ''
          }`}
          style={{ paddingLeft: `${level * 20}px` }}>
          {showCheckboxes && (
            <input
              type="checkbox"
              checked={isFolderSelected}
              onChange={() => handleFolderCheckbox(node)}
              onClick={(e) => e.stopPropagation()}
              className="w-4 h-4 text-blue-600"
            />
          )}
          <div className="flex items-center gap-1 flex-1 cursor-pointer" onClick={handleToggle}>
            <span className="text-gray-600">{isExpanded ? '▼' : '▶'}</span>
            <span className="text-blue-600">📁</span>
            <span className="text-sm font-medium">{node.name}</span>
            <span className="text-xs text-gray-500">({node.children?.length || 0})</span>
          </div>
        </div>
        {isExpanded && node.children && (
          <div>
            {node.children.map((child, idx) => (
              <FolderTree 
                key={idx}
                node={child}
                level={level + 1}
              />
            ))}
          </div>
        )}
      </div>
    );
  };

  const handleSelectAll = () => {
    if (!projectStructure) return;
    
    const allFiles = extractAllCompatibleFiles(projectStructure);
    
    if (selectedFiles.length === allFiles.length) {
      // Desmarcar todo
      setSelectedFiles([]);
      setSelectedFolders([]);
    } else {
      // Marcar todo
      setSelectedFiles(allFiles);
    }
  };

  // ============================================================================
  // UTILIDADES
  // ============================================================================

  const findFirstCompatibleFile = (node) => {
    if (node.type === 'file' && isCompatibleFile(node.name, 'visualization')) {
      return node;
    }
    if (node.children) {
      for (const child of node.children) {
        const found = findFirstCompatibleFile(child);
        if (found) return found;
      }
    }
    return null;
  };

  const extractAllCompatibleFiles = (node) => {
    let files = [];
    if (node.type === 'file' && isCompatibleFile(node.name, activeTab)) {
      files.push(node);
    }
    if (node.children) {
      for (const child of node.children) {
        files = files.concat(extractAllCompatibleFiles(child));
      }
    }
    return files;
  };

  const autoLoadFirstImage = async (fileNode) => {
    if (!fileNode || !isCompatibleFile(fileNode.name, 'visualization')) return;
    
    setSelectedFile(fileNode);
    setImageLoaded(false);

    try {
      const response = await fetch(`${JULIA_API}/api/load-image`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          filename: fileNode.name
        })
      });

      const result = await response.json();
      
      if (result.success) {
        setImageDimensions(result.dimensions);
        setImageLoaded(true);
        
        const midSagittal = Math.floor(result.dimensions[0] / 2);
        const midCoronal = Math.floor(result.dimensions[1] / 2);
        const midAxial = Math.floor(result.dimensions[2] / 2);
        
        await Promise.all([
          loadSlice('sagittal', midSagittal),
          loadSlice('coronal', midCoronal),
          loadSlice('axial', midAxial)
        ]);
      }
    } catch (error) {
      console.error('Error cargando imagen:', error);
    }
  };

  const uploadFileToServer = async (file) => {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      
      reader.onload = async () => {
        try {
          const base64data = reader.result.split(',')[1];
          
          const response = await fetch(`${JULIA_API}/api/upload-file`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              filename: file.name,
              data: base64data
            })
          });
          
          const result = await response.json();
          resolve(result);
        } catch (error) {
          reject(error);
        }
      };
      
      reader.onerror = reject;
      reader.readAsDataURL(file);
    });
  };

  const saveImage = async (orientation, sliceNum, imageData) => {
    if (!imageData || !selectedFile) {
      alert('No hay imagen para guardar');
      return;
    }

    try {
      const response = await fetch(`${JULIA_API}/api/guardar-imagen`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          nombre_archivo: `${selectedFile.name.split('.')[0]}_${orientation}_corte${sliceNum}.png`,
          imagen_base64: imageData.split(',')[1]
        })
      });

      const result = await response.json();
      
      if (result.success) {
        alert(`✅ Imagen guardada en:\n${result.ruta_completa}`);
      } else {
        alert(`❌ Error: ${result.error}`);
      }
    } catch (error) {
      console.error('Error:', error);
      alert('Error de conexión');
    }
  };

  const loadSlice = async (orientation, sliceNum) => {
    if (!selectedFile) return;

    try {
      const response = await fetch(`${JULIA_API}/api/get-slice`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          filename: selectedFile.name,
          orientation: orientation,
          slice: sliceNum
        })
      });

      const result = await response.json();
      
      if (result.success) {
        setSlices(prev => ({
          ...prev,
          [orientation]: {
            num: sliceNum,
            image: result.image
          }
        }));
      }
    } catch (error) {
      console.error('Error cargando corte:', error);
    }
  };

  const handleBack = () => {
    setCurrentView('home');
    setProjectStructure(null);
    setSelectedFile(null);
    setImageLoaded(false);
    setProjectPath('');
    setSelectedFiles([]);
    setSelectedFolders([]);
  };

  const testJuliaConnection = async () => {
    await checkJuliaConnection();
  };

  const handleTabChange = (tab) => {
    setActiveTab(tab);
    setSelectedFiles([]);
    setSelectedFolders([]);
    if (tab === 'radiomics') {
      setMultipleFilesMode(true);
    }
    if (tab === 'statistics') {
      // En estadísticas, pre-seleccionar carpetas de primer nivel si existen
      if (projectStructure && projectStructure.children) {
        const firstLevelFolders = projectStructure.children.filter(child => child.type === 'folder');
        setSelectedFolders(firstLevelFolders);
      }
    }
  };

  const handleStartStatistics = async () => {
  // Validación inicial: debe haber archivos seleccionados
  if (selectedFiles.length === 0) {
    alert('⚠️  Debes seleccionar archivos de al menos 2 grupos diferentes');
    return;
  }

  setStatisticsRunning(true);
  setStatisticsResults(null);

  try {
    // NUEVA LÓGICA: Extraer grupos DIRECTAMENTE de los paths de selectedFiles
    const grupos = {};
    
    // Contadores para validación
    let archivosIgnorados = 0;
    let archivosIncorrectos = 0;
    
    for (const file of selectedFiles) {
      // Normalizar separadores (Windows usa \ y web usa /)
      const normalizedPath = file.path.replace(/\\/g, '/');
      const pathParts = normalizedPath.split('/');
      
      // DEBUG: Mostrar estructura de path
      console.log(`🔍 Analizando: ${file.name}`);
      console.log(`   Path: ${normalizedPath}`);
      console.log(`   Niveles: ${pathParts.length}`);
      
      // VALIDACIÓN: Estructura debe ser Grupo/archivo (2 niveles)
      if (pathParts.length < 2) {
        // Estructura incorrecta: archivo en raíz sin grupo
        console.warn(`   ⚠️ ESTRUCTURA INCORRECTA: Archivo sin carpeta de grupo`);
        archivosIncorrectos++;
        continue; // Saltar este archivo
      }
      
      if (pathParts.length > 2) {
        // Estructura con subcarpetas adicionales (más de 2 niveles)
        console.warn(`   ⚠️ IGNORADO: Archivo anidado en subcarpetas (${pathParts.length} niveles)`);
        console.warn(`   → Se esperaba: Grupo/archivo`);
        console.warn(`   → Se recibió: ${pathParts.join('/')}`);
        archivosIgnorados++;
        continue; // Saltar este archivo
      }
      
      // ESTRUCTURA CORRECTA: Exactamente 2 niveles
      // pathParts = ["Grupo", "archivo.nii.gz"]
      // Tomar penúltimo elemento (índice length-2) = primer elemento (índice 0)
      const nombreGrupo = pathParts[pathParts.length - 2];
      
      console.log(`   ✅ Grupo asignado: "${nombreGrupo}"`);
      
      // Inicializar array si no existe
      if (!grupos[nombreGrupo]) {
        grupos[nombreGrupo] = [];
      }
      
      // Agregar el archivo al grupo
      grupos[nombreGrupo].push(file.name);
    }
    
    // Advertencias al usuario si hubo problemas
    if (archivosIncorrectos > 0) {
      console.warn(`\n⚠️ ${archivosIncorrectos} archivo(s) con estructura incorrecta (menos de 3 niveles)`);
      alert(`⚠️ Advertencia:\n\n${archivosIncorrectos} archivo(s) no siguen la estructura correcta.\n\nEstructura esperada:\n  Proyecto/Grupo/archivo.nii.gz\n\nEstos archivos fueron ignorados. Revisa la consola (F12) para detalles.`);
    }
    
    if (archivosIgnorados > 0) {
      console.warn(`\n⚠️ ${archivosIgnorados} archivo(s) ignorados (más de 3 niveles - subcarpetas)`);
      alert(`⚠️ ${archivosIgnorados} archivo(s) fueron ignorados.\n\nMotivo: Están dentro de subcarpetas adicionales.\n\nEstructura esperada:\n  Proyecto/Grupo/archivo.nii.gz\n\nNo use:\n  Proyecto/Grupo/Subcarpeta/archivo.nii.gz`);
    }

    // Validar que tengamos al menos 2 grupos
    const numGrupos = Object.keys(grupos).length;
    
    if (numGrupos < 2) {
      alert(`⚠️  Solo se detectó ${numGrupos} grupo.\n\nPara análisis estadístico necesitas seleccionar archivos de al menos 2 carpetas diferentes.\n\nGrupo encontrado: ${Object.keys(grupos)[0]}`);
      setStatisticsRunning(false);
      return;
    }

    // Debug: Mostrar estructura de grupos en consola
    console.log('📊 Grupos detectados:', grupos);
    console.log(`   Total de grupos: ${numGrupos}`);
    for (const [nombre, archivos] of Object.entries(grupos)) {
      console.log(`   - ${nombre}: ${archivos.length} archivos`);
    }

      // Preparar pruebas seleccionadas
  
	// VALIDACIÓN DE REQUISITOS POR PRUEBA
	const requisitos = {
	  tTest: { minGrupos: 2, nombre: "Prueba T de Student" },
	  anova: { minGrupos: 3, nombre: "ANOVA / ANCOVA" },
	  correlation: { minGrupos: 2, nombre: "Test de Correlación" },
	  multipleComparisons: { minGrupos: 3, nombre: "Comparaciones Múltiples" },
	  nonParametric: { minGrupos: 2, nombre: "Pruebas No Paramétricas" },
	  fisherVariance: { minGrupos: 2, nombre: "Prueba F de Fisher" },
	  correlationMatrix: { minGrupos: 2, nombre: "Matriz de Correlación" },
	  zVariance: { minGrupos: 2, nombre: "Prueba Z de Varianzas" }
	};

	// Filtrar pruebas según requisitos
	const pruebasSeleccionadas = Object.keys(selectedTests).filter(key => selectedTests[key]);
	const pruebasValidas = [];
	const pruebasRechazadas = [];

	for (const prueba of pruebasSeleccionadas) {
	  const req = requisitos[prueba];
	  if (req && numGrupos < req.minGrupos) {
	    pruebasRechazadas.push({
	      nombre: req.nombre,
	      requiere: req.minGrupos,
	      actual: numGrupos
	    });
	  } else {
	    pruebasValidas.push(prueba);
	  }
	}

	// Mostrar advertencia si hay pruebas rechazadas
	if (pruebasRechazadas.length > 0) {
	  const mensajeRechazadas = pruebasRechazadas.map(p => 
	    `• ${p.nombre}: requiere ${p.requiere} grupos (tienes ${p.actual})`
	  ).join('\n');
  
	  alert(`⚠️ Algunas pruebas no se pueden realizar:\n\n${mensajeRechazadas}\n\nLas demás pruebas se ejecutarán normalmente.`);
	  
	  console.warn('⚠️ Pruebas rechazadas por falta de grupos:');
	  pruebasRechazadas.forEach(p => {
	    console.warn(`   • ${p.nombre}: necesita ${p.requiere} grupos, tiene ${p.actual}`);
  	  });
	}

	// Si no hay pruebas válidas, cancelar
	if (pruebasValidas.length === 0) {
  	  alert('❌ Ninguna de las pruebas seleccionadas puede realizarse con el número actual de grupos.');
  	  setStatisticsRunning(false);
  	  return;
	}

	console.log(`✅ Pruebas que se ejecutarán: ${pruebasValidas.length}`);
	console.log(`   ${pruebasValidas.map(p => requisitos[p]?.nombre || p).join(', ')}`);

	// Siempre incluir normalityTest (obligatorio)
	const pruebasFinales = ['normalityTest', ...pruebasValidas];

      const response = await fetch(`${JULIA_API}/api/analisis-estadistico`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          grupos: grupos,
          pruebas: pruebasFinales,
          comparar_por_archivos: compareByFiles,
          tipo_datos: selectedFiles.some(f => f.name.match(/\.(xlsx|xls)$/i)) ? 'excel' : 'imagenes'
        })
      });

      const result = await response.json();

      if (result.success) {
        setStatisticsResults(result.resultados);
        alert(`✅ Análisis estadístico completado`);
      } else {
        alert(`❌ Error: ${result.error}`);
      }
    } catch (error) {
      console.error('Error:', error);
      alert('Error de conexión con el servidor');
    } finally {
      setStatisticsRunning(false);
    }
  };

  const toggleTest = (testKey) => {
    setSelectedTests(prev => ({
      ...prev,
      [testKey]: !prev[testKey]
    }));
  };

  const handleStartRadiomics = async () => {
    const filesToAnalyze = multipleFilesMode 
      ? selectedFiles.length > 0 
        ? selectedFiles 
        : extractAllCompatibleFiles(projectStructure || {})
      : selectedFile 
        ? [selectedFile] 
        : [];

    if (filesToAnalyze.length === 0) {
      alert('No hay archivos seleccionados');
      return;
    }

    setRadiomicsRunning(true);
    setRadiomicsResults(null);

    try {
      const response = await fetch(`${JULIA_API}/api/analisis-radiomico`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          archivos: filesToAnalyze.map(f => f.name),
          modo_paralelo: parallelMode
        })
      });

      const result = await response.json();
      
      if (result.success) {
        setRadiomicsResults(result.resultados);
        alert(`✅ Análisis completado\n${filesToAnalyze.length} archivo(s) procesado(s)`);
      } else {
        alert(`❌ Error: ${result.error}`);
      }
    } catch (error) {
      console.error('Error:', error);
      alert('Error de conexión');
    } finally {
      setRadiomicsRunning(false);
    }
  };

  // ============================================================================
  // RENDERIZADO PRINCIPAL
  // ============================================================================

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100">
      {loadingFiles && (
        <div className="fixed inset-0 bg-black bg-opacity-50 z-50 flex items-center justify-center">
          <div className="bg-white rounded-2xl p-8 max-w-md w-full shadow-2xl">
            <div className="text-center">
              <Activity className="text-blue-600 mx-auto mb-4 animate-spin" size={48} />
              <h2 className="text-xl font-bold text-gray-800 mb-2">Procesando</h2>
              <p className="text-gray-600 mb-4">{loadingMessage}</p>
              <div className="w-full h-2 bg-gray-200 rounded-full overflow-hidden">
                <div className="h-full bg-blue-600 rounded-full animate-pulse" style={{width: '100%'}}></div>
              </div>
            </div>
          </div>
        </div>
      )}
      
      <input
        ref={fileInputRef}
        type="file"
        webkitdirectory="true"
        directory="true"
        multiple
        onChange={handleFileChange}
        style={{ display: 'none' }}
      />

      <input
        ref={addFilesInputRef}
        type="file"
        multiple
        onChange={handleAddFilesChange}
        style={{ display: 'none' }}
      />

      <div className="fixed top-4 right-4 z-50 flex items-center gap-2">
        <div 
          onClick={testJuliaConnection}
          className={`w-3 h-3 rounded-full cursor-pointer ${
            juliaStatus === 'connected' 
              ? 'bg-green-500' 
              : juliaStatus === 'checking'
              ? 'bg-yellow-500'
              : 'bg-red-500'
          }`}
          title={`Julia: ${juliaStatus}`}
        />
      </div>

      {currentView === 'home' ? (
        <div className="flex items-center justify-center min-h-screen">
          <div className="bg-white rounded-2xl shadow-2xl p-12 max-w-md w-full">
            <div className="flex items-center justify-center mb-4">
              <Activity className="text-blue-600" size={48} />
            </div>
            <h1 className="text-3xl font-bold text-gray-800 mb-2 text-center">
              MSL Process
            </h1>
            <p className="text-gray-500 text-center mb-8">
              Sistema de Análisis de Imágenes Médicas
            </p>
            
            {juliaInfo && (
              <div className="mb-6 p-3 bg-green-50 border border-green-200 rounded-lg">
                <p className="text-xs text-green-700 text-center">
                  ✓ Backend activo - Julia {juliaInfo.julia_version}
                </p>
                {juliaInfo.native_file_dialog && (
                  <p className="text-xs text-green-600 text-center mt-1">
                    🎯 Selector nativo disponible
                  </p>
                )}
              </div>
            )}
            
            <div className="space-y-4">
              <button
                onClick={handleOpenProject}
                className="w-full flex items-center justify-center gap-3 bg-blue-600 hover:bg-blue-700 text-white font-semibold py-4 px-6 rounded-xl transition-all duration-200 transform hover:scale-105 shadow-lg">
                <FolderOpen size={24} />
                Abrir Proyecto
              </button>
              
              <button
                onClick={handleCreateProject}
                className="w-full flex items-center justify-center gap-3 bg-indigo-600 hover:bg-indigo-700 text-white font-semibold py-4 px-6 rounded-xl transition-all duration-200 transform hover:scale-105 shadow-lg">
                <FolderPlus size={24} />
                Crear Nuevo Proyecto
              </button>
            </div>

            <div className="mt-8 pt-6 border-t border-gray-200">
              <p className="text-xs text-gray-400 text-center">
                Compatible con NIfTI (.nii, .nii.gz) y DICOM
              </p>
            </div>
          </div>
        </div>
      ) : (
        <div className="min-h-screen p-6">
          <div className="mb-6 flex items-center justify-between">
            <button
              onClick={handleBack}
              className="flex items-center gap-2 bg-white hover:bg-gray-50 text-gray-700 font-medium py-2 px-4 rounded-lg shadow-md transition-all duration-200 hover:shadow-lg">
              <ArrowLeft size={20} />
              Volver
            </button>
            
            <div className="flex items-center gap-3">
              {projectPath && (
                <div className="bg-white px-4 py-2 rounded-lg shadow-md">
                  <p className="text-xs text-gray-500">Proyecto:</p>
                  <p className="text-sm font-medium text-gray-700 truncate max-w-md">{projectPath}</p>
                </div>
              )}
              
              <button
                onClick={handleAddFiles}
                className="flex items-center gap-2 bg-purple-600 hover:bg-purple-700 text-white font-medium py-2 px-4 rounded-lg shadow-md transition-all">
                <Upload size={18} />
                Agregar Archivos
              </button>
              
              <button
                onClick={handleAddGroups}
                className="flex items-center gap-2 bg-indigo-600 hover:bg-indigo-700 text-white font-medium py-2 px-4 rounded-lg shadow-md transition-all">
                <Plus size={18} />
                Agregar Grupos
              </button>
            </div>
          </div>

          <div className="flex gap-6 h-[calc(100vh-120px)]">
            <aside className="w-64 bg-white rounded-xl shadow-lg p-4 overflow-y-auto">
              <div className="flex items-center justify-between mb-3">
                <h3 className="text-sm font-semibold text-gray-600">
                  Estructura del Proyecto
                </h3>
                {(activeTab === 'radiomics' || activeTab === 'statistics') && projectStructure && (
                  <button
                    onClick={handleSelectAll}
                    className="text-xs text-blue-600 hover:text-blue-800 font-medium"
                    title="Marcar/Desmarcar todo">
                    {selectedFiles.length === extractAllCompatibleFiles(projectStructure).length ? '☑' : '☐'} Todo
                  </button>
                )}
              </div>
              
              {projectStructure ? (
                <FolderTree node={projectStructure} />
              ) : (
                <p className="text-xs text-gray-400 text-center mt-8">
                  Cargando estructura...
                </p>
              )}
            </aside>

            <main className="flex-1 bg-white rounded-xl shadow-lg overflow-hidden">
              <div className="border-b border-gray-200 px-6 pt-4">
                <div className="flex gap-2">
                  <button
                    onClick={() => handleTabChange('visualization')}
                    className={`px-4 py-2 font-medium text-sm rounded-t-lg transition-all ${
                      activeTab === 'visualization'
                        ? 'bg-blue-500 text-white'
                        : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                    }`}>
                    Visualización
                  </button>
                  <button
                    onClick={() => handleTabChange('radiomics')}
                    className={`px-4 py-2 font-medium text-sm rounded-t-lg transition-all ${
                      activeTab === 'radiomics'
                        ? 'bg-blue-500 text-white'
                        : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                    }`}>
                    Radiómica
                  </button>
                  <button
                    onClick={() => handleTabChange('statistics')}
                    className={`px-4 py-2 font-medium text-sm rounded-t-lg transition-all ${
                      activeTab === 'statistics'
                        ? 'bg-blue-500 text-white'
                        : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                    }`}>
                    Estadísticas
                  </button>
                </div>
              </div>

              <div className="p-6 h-[calc(100%-60px)] overflow-y-auto">
                {activeTab === 'visualization' && (
                  <div className="h-full">
                    {!selectedFile ? (
                      <div className="flex items-center justify-center h-full">
                        <p className="text-gray-400 text-lg">
                          Selecciona un archivo del árbol
                        </p>
                      </div>
                    ) : !imageLoaded ? (
                      <div className="flex flex-col items-center justify-center h-full">
                        <Activity className="text-blue-600 animate-spin mb-4" size={48} />
                        <p className="text-gray-500">Cargando imagen...</p>
                      </div>
                    ) : (
                      <div className="grid grid-cols-2 grid-rows-2 gap-4 h-full">
                        <div className="bg-gray-50 rounded-lg p-4 flex flex-col">
                          <div className="flex items-center justify-between mb-2">
                            <h3 className="font-semibold text-gray-700">Corte Sagital</h3>
                            <div className="flex items-center gap-2">
                              <input
                                type="number"
                                min="1"
                                max={imageDimensions?.[0] || 1}
                                value={slices.sagittal.num}
                                onChange={(e) => loadSlice('sagittal', parseInt(e.target.value))}
                                className="w-16 px-2 py-1 border border-gray-300 rounded text-sm"
                              />
                              <span className="text-sm text-gray-500">/ {imageDimensions?.[0]}</span>
                              <button
                                onClick={() => saveImage('sagittal', slices.sagittal.num, slices.sagittal.image)}
                                className="ml-2 p-1.5 bg-blue-500 hover:bg-blue-600 text-white rounded transition-colors"
                                title="Guardar imagen">
                                💾
                              </button>
                            </div>
                          </div>
                          <div className="flex-1 flex items-center justify-center bg-black rounded">
                            {slices.sagittal.image ? (
                              <img src={slices.sagittal.image} alt="Sagital" className="max-h-full max-w-full object-contain" />
                            ) : (
                              <p className="text-gray-500">Cargando...</p>
                            )}
                          </div>
                        </div>

                        <div className="bg-gray-50 rounded-lg p-4 flex flex-col">
                          <div className="flex items-center justify-between mb-2">
                            <h3 className="font-semibold text-gray-700">Corte Coronal</h3>
                            <div className="flex items-center gap-2">
                              <input
                                type="number"
                                min="1"
                                max={imageDimensions?.[1] || 1}
                                value={slices.coronal.num}
                                onChange={(e) => loadSlice('coronal', parseInt(e.target.value))}
                                className="w-16 px-2 py-1 border border-gray-300 rounded text-sm"
                              />
                              <span className="text-sm text-gray-500">/ {imageDimensions?.[1]}</span>
                              <button
                                onClick={() => saveImage('coronal', slices.coronal.num, slices.coronal.image)}
                                className="ml-2 p-1.5 bg-blue-500 hover:bg-blue-600 text-white rounded transition-colors"
                                title="Guardar imagen">
                                💾
                              </button>
                            </div>
                          </div>
                          <div className="flex-1 flex items-center justify-center bg-black rounded">
                            {slices.coronal.image ? (
                              <img src={slices.coronal.image} alt="Coronal" className="max-h-full max-w-full object-contain" />
                            ) : (
                              <p className="text-gray-500">Cargando...</p>
                            )}
                          </div>
                        </div>

                        <div className="bg-gray-50 rounded-lg p-4 flex flex-col">
                          <h3 className="font-semibold text-gray-700 mb-3">Información</h3>
                          <div className="space-y-2 text-sm">
                            <div className="flex justify-between">
                              <span className="text-gray-600">Archivo:</span>
                              <span className="font-medium text-gray-800 truncate ml-2">{selectedFile?.name}</span>
                            </div>
                            <div className="flex justify-between">
                              <span className="text-gray-600">Dimensiones:</span>
                              <span className="font-medium text-gray-800">
                                {imageDimensions?.join(' × ')}
                              </span>
                            </div>
                            {projectPath && (
                              <div className="mt-4 pt-4 border-t border-gray-300">
                                <span className="text-gray-600 text-xs">Proyecto:</span>
                                <p className="font-medium text-gray-800 text-xs mt-1 break-all">
                                  {projectPath}
                                </p>
                              </div>
                            )}
                          </div>
                        </div>

                        <div className="bg-gray-50 rounded-lg p-4 flex flex-col">
                          <div className="flex items-center justify-between mb-2">
                            <h3 className="font-semibold text-gray-700">Corte Axial</h3>
                            <div className="flex items-center gap-2">
                              <input
                                type="number"
                                min="1"
                                max={imageDimensions?.[2] || 1}
                                value={slices.axial.num}
                                onChange={(e) => loadSlice('axial', parseInt(e.target.value))}
                                className="w-16 px-2 py-1 border border-gray-300 rounded text-sm"
                              />
                              <span className="text-sm text-gray-500">/ {imageDimensions?.[2]}</span>
                              <button
                                onClick={() => saveImage('axial', slices.axial.num, slices.axial.image)}
                                className="ml-2 p-1.5 bg-blue-500 hover:bg-blue-600 text-white rounded transition-colors"
                                title="Guardar imagen">
                                💾
                              </button>
                            </div>
                          </div>
                          <div className="flex-1 flex items-center justify-center bg-black rounded">
                            {slices.axial.image ? (
                              <img src={slices.axial.image} alt="Axial" className="max-h-full max-w-full object-contain" />
                            ) : (
                              <p className="text-gray-500">Cargando...</p>
                            )}
                          </div>
                        </div>
                      </div>
                    )}
                  </div>
                )}

                {activeTab === 'radiomics' && (
                  <div className="h-full flex gap-4">
                    {/* PANEL IZQUIERDO - Controles */}
                    <div className="w-80 flex-shrink-0">
                      <h2 className="text-2xl font-bold text-gray-800 mb-4">Análisis Radiómico</h2>
                      
                      <div className="bg-gray-50 rounded-lg p-4 mb-4">
                        <div className="space-y-3">
                          <div className="flex items-center gap-3">
                            <input
                              type="checkbox"
                              id="multipleFiles"
                              checked={multipleFilesMode}
                              onChange={(e) => setMultipleFilesMode(e.target.checked)}
                              className="w-4 h-4 text-blue-600"
                            />
                            <label htmlFor="multipleFiles" className="text-sm font-medium text-gray-700">
                              Analizar múltiples archivos
                            </label>
                          </div>
                          
                          <div className="flex items-center gap-3">
                            <input
                              type="checkbox"
                              id="parallelMode"
                              checked={parallelMode}
                              onChange={(e) => setParallelMode(e.target.checked)}
                              className="w-4 h-4 text-blue-600"
                            />
                            <label htmlFor="parallelMode" className="text-sm font-medium text-gray-700">
                              Procesamiento en paralelo
                            </label>
                          </div>
                        </div>
                      </div>

                      <button
                        onClick={handleStartRadiomics}
                        disabled={radiomicsRunning}
                        className={`w-full px-6 py-3 rounded-lg font-semibold transition-all ${
                          radiomicsRunning
                            ? 'bg-gray-400 cursor-not-allowed'
                            : 'bg-green-600 hover:bg-green-700 transform hover:scale-105'
                        } text-white shadow-lg`}>
                        {radiomicsRunning ? 'Analizando...' : 'Iniciar Análisis Radiómico'}
                      </button>

                      {radiomicsRunning && radiomicsProgress > 0 && (
                        <div className="mt-4 p-4 bg-blue-50 rounded-lg border border-blue-200">
                          <div className="flex items-center justify-between mb-2">
                            <span className="text-sm font-medium text-blue-800">
                              Procesando archivos...
                            </span>
                            <span className="text-sm font-semibold text-blue-900">
                              {Math.round(radiomicsProgress)}%
                            </span>
                          </div>
                          <div className="w-full h-3 bg-blue-200 rounded-full overflow-hidden">
                            <div 
                              className="h-full bg-blue-600 transition-all duration-1000 ease-linear rounded-full"
                              style={{ width: `${radiomicsProgress}%` }}
                            />
                          </div>
                          <p className="text-xs text-blue-700 mt-2">
                            {radiomicsProgress >= 95 
                              ? 'Finalizando análisis...' 
                              : 'Tiempo estimado restante: ~' + Math.ceil((100 - radiomicsProgress) * (parallelMode ? 15 : 30) / 100) + 's'}
                          </p>
                        </div>
                      )}

                      {multipleFilesMode && projectStructure && !radiomicsRunning && (
                        <div className="mt-4 p-3 bg-blue-50 rounded-lg border border-blue-200">
                          <p className="text-sm text-blue-800">
                            {selectedFiles.length > 0
                              ? `${selectedFiles.length} archivo(s) seleccionado(s)`
                              : `Se analizarán todos los archivos compatibles (${extractAllCompatibleFiles(projectStructure).length})`}
                          </p>
                        </div>
                      )}
                    </div>

                    {/* PANEL DERECHO - Resultados */}
                    <div className="flex-1 flex flex-col min-w-0">
                      {radiomicsResults ? (
                        <>
                          <h3 className="text-lg font-semibold text-gray-700 mb-3">Resultados</h3>
                          <div className="flex-1 overflow-auto bg-white rounded-lg border border-gray-200">
                            <table className="min-w-full divide-y divide-gray-200">
                              <thead className="bg-gray-50 sticky top-0">
                                <tr>
                                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                                    Archivo
                                  </th>
                                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                                    Características
                                  </th>
                                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                                    Estado
                                  </th>
                                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                                    Acción
                                  </th>
                                </tr>
                              </thead>
                              <tbody className="bg-white divide-y divide-gray-200">
                                {radiomicsResults.map((result, idx) => (
                                  <React.Fragment key={idx}>
                                    <tr className="hover:bg-gray-50">
                                      <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                                        {result.archivo}
                                      </td>
                                      <td className="px-6 py-4 text-sm text-gray-500">
                                        {result.num_caracteristicas || '-'} features
                                      </td>
                                      <td className="px-6 py-4 whitespace-nowrap">
                                        <span className={`px-2 inline-flex text-xs leading-5 font-semibold rounded-full ${
                                          result.success 
                                            ? 'bg-green-100 text-green-800' 
                                            : 'bg-red-100 text-red-800'
                                        }`}>
                                          {result.success ? '✓ Completado' : '✗ Error'}
                                        </span>
                                      </td>
                                      <td className="px-6 py-4 whitespace-nowrap text-sm">
                                        {result.success && (
                                          <button
                                            onClick={() => setExpandedResult(expandedResult === idx ? null : idx)}
                                            className="text-blue-600 hover:text-blue-800 font-medium">
                                            {expandedResult === idx ? '▼ Ocultar' : '▶ Ver detalles'}
                                          </button>
                                        )}
                                      </td>
                                    </tr>
                                    {expandedResult === idx && result.success && (
                                      <tr>
                                        <td colSpan="4" className="px-6 py-4 bg-gray-50">
                                          <div className="space-y-3">
                                            {result.caracteristicas && Object.entries(result.caracteristicas).map(([categoria, features]) => (
                                              <div key={categoria} className="border-l-4 border-blue-500 pl-4">
                                                <h4 className="font-semibold text-gray-700 mb-2 capitalize">
                                                  {categoria.replace(/_/g, ' ')}
                                                </h4>
                                                <div className="grid grid-cols-2 md:grid-cols-3 gap-2 text-sm">
                                                  {Object.entries(features).map(([key, value]) => (
                                                    <div key={key} className="bg-white p-2 rounded">
                                                      <span className="text-gray-600">{key}:</span>{' '}
                                                      <span className="font-medium text-gray-900">
                                                        {typeof value === 'number' ? value.toFixed(4) : value}
                                                      </span>
                                                    </div>
                                                  ))}
                                                </div>
                                              </div>
                                            ))}
                                          </div>
                                        </td>
                                      </tr>
                                    )}
                                  </React.Fragment>
                                ))}
                              </tbody>
                            </table>
                          </div>
                        </>
                      ) : (
                        <div className="flex-1 flex items-center justify-center">
                          <p className="text-gray-400 text-lg">
                            Selecciona archivos e inicia el análisis
                          </p>
                        </div>
                      )}
                    </div>
                  </div>
                )}

                {activeTab === 'statistics' && (
                  <div className="h-full flex gap-4">
                    {/* PANEL IZQUIERDO - Opciones */}
                    <div className="w-80 flex-shrink-0">
                      <h2 className="text-2xl font-bold text-gray-800 mb-4">Análisis Estadístico</h2>
                      
                      <div className="bg-gray-50 rounded-lg p-4 mb-4">
                        <h3 className="font-semibold text-gray-700 mb-3">Pruebas a Realizar</h3>
                        <div className="space-y-2 max-h-64 overflow-y-auto">
                              
                   
                          <div className="flex items-center gap-2">
                            <input
                              type="checkbox"
                              id="tTest"
                              checked={selectedTests.tTest}
                              onChange={() => toggleTest('tTest')}
                              className="w-4 h-4 text-blue-600"
                            />
                            <label htmlFor="tTest" className="text-sm text-gray-700">
                              Prueba T de Student
                            </label>
                          </div>
                          
                          <div className="flex items-center gap-2">
                            <input
                              type="checkbox"
                              id="anova"
                              checked={selectedTests.anova}
                              onChange={() => toggleTest('anova')}
                              className="w-4 h-4 text-blue-600"
                            />
                            <label htmlFor="anova" className="text-sm text-gray-700">
                              ANOVA / ANCOVA
                            </label>
                          </div>
                          
                          <div className="flex items-center gap-2">
                            <input
                              type="checkbox"
                              id="correlation"
                              checked={selectedTests.correlation}
                              onChange={() => toggleTest('correlation')}
                              className="w-4 h-4 text-blue-600"
                            />
                            <label htmlFor="correlation" className="text-sm text-gray-700">
                              Test de Correlación
                            </label>
                          </div>
                          
                          <div className="flex items-center gap-2">
                            <input
                              type="checkbox"
                              id="multipleComparisons"
                              checked={selectedTests.multipleComparisons}
                              onChange={() => toggleTest('multipleComparisons')}
                              className="w-4 h-4 text-blue-600"
                            />
                            <label htmlFor="multipleComparisons" className="text-sm text-gray-700">
                              Comparaciones Múltiples (Tukey/Bonferroni)
                            </label>
                          </div>
                          
                          <div className="flex items-center gap-2">
                            <input
                              type="checkbox"
                              id="nonParametric"
                              checked={selectedTests.nonParametric}
                              onChange={() => toggleTest('nonParametric')}
                              className="w-4 h-4 text-blue-600"
                            />
                            <label htmlFor="nonParametric" className="text-sm text-gray-700">
                              Pruebas No Paramétricas (Mann-Whitney/Kruskal-Wallis)
                            </label>
                          </div>
                          
                          <div className="flex items-center gap-2">
                            <input
                              type="checkbox"
                              id="fisherVariance"
                              checked={selectedTests.fisherVariance}
                              onChange={() => toggleTest('fisherVariance')}
                              className="w-4 h-4 text-blue-600"
                            />
                            <label htmlFor="fisherVariance" className="text-sm text-gray-700">
                              Prueba F de Fisher (Varianzas)
                            </label>
                          </div>
                          
                          <div className="flex items-center gap-2">
                            <input
                              type="checkbox"
                              id="correlationMatrix"
                              checked={selectedTests.correlationMatrix}
                              onChange={() => toggleTest('correlationMatrix')}
                              className="w-4 h-4 text-blue-600"
                            />
                            <label htmlFor="correlationMatrix" className="text-sm text-gray-700">
                              Matriz de Correlación (R y p-valor)
                            </label>
                          </div>
                          
                          <div className="flex items-center gap-2">
                            <input
                              type="checkbox"
                              id="zVariance"
                              checked={selectedTests.zVariance}
                              onChange={() => toggleTest('zVariance')}
                              className="w-4 h-4 text-blue-600"
                            />
                            <label htmlFor="zVariance" className="text-sm text-gray-700">
                              Prueba Z de Varianzas
                            </label>
                          </div>
                        </div>
                      </div>

                      {/* Opción para Excel */}
                      {selectedFiles.some(f => f.name.match(/\.(xlsx|xls)$/i)) && (
                        <div className="bg-yellow-50 rounded-lg p-4 mb-4 border border-yellow-200">
                          <h3 className="font-semibold text-yellow-800 mb-2 text-sm">Archivos Excel detectados</h3>
                          <div className="flex items-center gap-2">
                            <input
                              type="checkbox"
                              id="compareByFiles"
                              checked={compareByFiles}
                              onChange={(e) => setCompareByFiles(e.target.checked)}
                              className="w-4 h-4 text-yellow-600"
                            />
                            <label htmlFor="compareByFiles" className="text-sm text-yellow-800">
                              Comparar entre archivos (desmarcar para comparar entre carpetas)
                            </label>
                          </div>
                        </div>
                      )}

                      <button
                        onClick={handleStartStatistics}
                        disabled={statisticsRunning}
                        className={`w-full px-6 py-3 rounded-lg font-semibold transition-all ${
                          statisticsRunning
                            ? 'bg-gray-400 cursor-not-allowed'
                            : 'bg-purple-600 hover:bg-purple-700 transform hover:scale-105'
                        } text-white shadow-lg`}>
                        {statisticsRunning ? 'Analizando...' : 'Iniciar Análisis Estadístico'}
                      </button>

                      {/* Info de grupos seleccionados */}
                      <div className="mt-4 p-3 bg-blue-50 rounded-lg border border-blue-200">
                        <p className="text-sm font-medium text-blue-800 mb-2">
                          Grupos seleccionados: {selectedFolders.length}
                        </p>
                        {selectedFolders.length > 0 && (
                          <ul className="text-xs text-blue-700 space-y-1 max-h-32 overflow-y-auto">
                            {selectedFolders.map((folder, idx) => (
                              <li key={idx}>📁 {folder.name}</li>
                            ))}
                          </ul>
                        )}
                        {selectedFolders.length < 2 && (
                          <p className="text-xs text-red-600 mt-2">
                            ⚠️ Necesitas seleccionar al menos 2 grupos
                          </p>
                        )}
                      </div>
                    </div>

                    {/* PANEL DERECHO - Resultados */}
                    <div className="flex-1 flex flex-col min-w-0">
                      {statisticsResults ? (
  			<>
 			   <h3 className="text-lg font-semibold text-gray-700 mb-3">Resultados Estadísticos</h3>
			    <div className="flex-1 overflow-auto bg-white rounded-lg border border-gray-200">
			      <table className="min-w-full divide-y divide-gray-200">
			        <thead className="bg-gray-50 sticky top-0">
			          <tr>
			            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
			              Prueba
			            </th>
			            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
			              Estadístico
			            </th>
			            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
			              P-Valor
			            </th>
			            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
			              Conclusión
			            </th>
			          </tr>
			        </thead>
			        <tbody className="bg-white divide-y divide-gray-200">
			          {Object.entries(statisticsResults).map(([prueba, resultado], idx) => {
			            // Determinar nombre de la prueba
			            const nombresPruebas = {
			              normalityTest: "Test de Normalidad",
			              tTest: "Prueba T de Student",
			              anova: "ANOVA",
			              correlation: "Correlación",
			              multipleComparisons: "Comparaciones Múltiples",
			              nonParametric: "Pruebas No Paramétricas",
			              fisherVariance: "Prueba F de Fisher",
			              correlationMatrix: "Matriz de Correlación",
			              zVariance: "Prueba Z de Varianzas"
			            };
	
			            const nombrePrueba = nombresPruebas[prueba] || prueba;
			
			            // Extraer información según el tipo de resultado
			            let estadistico = '-';
			            let pValor = '-';
			            let conclusion = '-';

			            if (typeof resultado === 'object' && !resultado.error) {
			              // Test de Normalidad (puede tener múltiples grupos)
			              if (prueba === 'normalityTest') {
			                return Object.entries(resultado).map(([grupo, test], subIdx) => (
			                  <tr key={`${idx}-${subIdx}`} className="hover:bg-gray-50">
			                    <td className="px-6 py-4 text-sm font-medium text-gray-900">
			                      {subIdx === 0 ? nombrePrueba : ''} {grupo ? `(${grupo})` : ''}
			                    </td>
			                    <td className="px-6 py-4 text-sm text-gray-700">
			                      {test.W ? `W = ${test.W}` : '-'}
			                    </td>
			                    <td className="px-6 py-4 text-sm text-gray-700">
		     	                 {test.p_value || '-'}
		      	              </td>
		                    <td className="px-6 py-4 text-sm text-gray-600">
		                      {test.conclusion || '-'}
			                    </td>
		                  </tr>
		                ));
	              }

              // Otras pruebas
              if (resultado.t_statistic) estadistico = `t = ${resultado.t_statistic}`;
              else if (resultado.F_statistic) estadistico = `F = ${resultado.F_statistic}`;
              else if (resultado.U_statistic) estadistico = `U = ${resultado.U_statistic}`;
              else if (resultado.H_statistic) estadistico = `H = ${resultado.H_statistic}`;
              else if (resultado.Z_statistic) estadistico = `Z = ${resultado.Z_statistic}`;
              else if (resultado.r) estadistico = `r = ${resultado.r}`;
              else if (resultado.rho) estadistico = `ρ = ${resultado.rho}`;

              pValor = resultado.p_value || '-';
              conclusion = resultado.conclusion || resultado.test_aplicado || '-';
            }

            return (
              <tr key={idx} className="hover:bg-gray-50">
                <td className="px-6 py-4 text-sm font-medium text-gray-900">
                  {nombrePrueba}
                </td>
                <td className="px-6 py-4 text-sm text-gray-700">
                  {estadistico}
                </td>
                <td className="px-6 py-4 text-sm text-gray-700">
                  {pValor}
                </td>
                <td className="px-6 py-4 text-sm text-gray-600">
                  {conclusion}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  </>
) : (
                        <div className="flex-1 flex flex-col items-center justify-center">
                          <div className="text-purple-500 mb-4 text-5xl">📊</div>
                          <p className="text-gray-400 text-lg mb-2">
                            Selecciona grupos y pruebas estadísticas
                          </p>
                          <p className="text-gray-500 text-sm text-center max-w-md">
                            Marca al menos 2 carpetas en el árbol de archivos y selecciona las pruebas que deseas realizar
                          </p>
                        </div>
                      )}
                    </div>
                  </div>
                )}
              </div>
            </main>
          </div>
        </div>
      )}
    </div>
  );
}