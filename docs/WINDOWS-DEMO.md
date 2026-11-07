# ChaseLab_MM · demo Windows 0.1.0-demo.1

Primera adaptación experimental para Windows x64. Compilar correctamente no certifica la reproducción en Resolume: la salida GPU y la interfaz deben validarse con un tester. El instalador no está firmado con Authenticode.

## Instalar y probar

1. Descarga el instalador `ChaseLab_MM-Windows-x64-0.1.0-demo.1-Setup.exe` y comprueba su SHA256 frente a `SHA256SUMS.txt`.
2. Instálalo en Windows 10/11 x64. No requiere instalar .NET aparte ni privilegios de administrador.
3. Abre **ChaseLab_MM Windows Demo** desde Inicio. Se abre un proyecto con cuatro slices y cuatro pasos. Pulsa **▶ / Pausa**: la selección debe avanzar.
4. Prueba pintar celdas arrastrando, añadir/quitar pasos, copiar/pegar un paso, duración y Deshacer. Guardar el proyecto y volverlo a abrir debe conservar los cambios.
5. Guarda y cierra Arena. En el editor, **Instalar Player…** y selecciona la carpeta **Extra Effects** configurada en las preferencias de Arena. Si ya existe la DLL de esta demo, se respalda antes de reemplazarla. Si Arena mantiene el archivo abierto, cierra Arena y vuelve a intentar.
6. Abre Arena con un vídeo activo. Busca **CL Win Demo_MM** y colócalo en Composition. En el editor pulsa **Conectar Arena**. El efecto debe recortar el vídeo a los slices activos. Ambos programas deben ejecutarse con el mismo usuario de Windows.
7. La composición de Arena debe tener las mismas dimensiones que el montaje del editor. Para un montaje propio, usa **Importar XML…** con un preset de Advanced Output guardado. La importación guarda una copia del proyecto actual y crea una secuencia vacía: pulsa **Chase** para llenarla.
8. Prueba **Corte**, **Fade out**, **Pulso** y **BPM Arena**. El BPM se recibe desde el efecto; la fase de compás todavía no está sincronizada.
9. Desconecta el editor: el efecto debe dejar pasar el vídeo original en menos de un segundo. Una secuencia vacía conectada produce salida transparente: es el comportamiento de una máscara vacía.
10. Si algo falla, pulsa **Diagnóstico…** y entrega el informe, la versión exacta de Arena y el modelo de tarjeta gráfica. Revisa el informe antes de compartirlo: los errores pueden incluir rutas locales.

## Alcance real de esta demo

- Abrir/guardar proyectos Mac formatos 1–5 conservando campos opcionales desconocidos; validación de tamaños, coordenadas y duraciones. Formatos futuros se rechazan.
- Secuencias, pintura en matriz y polígonos, pasos +/−, copiar/pegar pasos, duración, Deshacer, zoom con rueda y desplazamiento con botón central.
- Reproducción de Corte/Fade out/Pulso y curvas Bézier incluidas en proyectos. La demo aún no dibuja curvas ni gestiona la biblioteca de envolventes.
- Player experimental con control desde el editor y modo de máscara. Su parámetro Level multiplica la intensidad. No es todavía el Player Mac completo: faltan Control → Arena, Fill/Stretch, Echoes y selectores por instancia.
- **Seguir XML guardado** sigue únicamente el archivo importado mientras la app está abierta. Conserva los pasos si el número, los nombres y el orden de slices coinciden. Cambios de cantidad/orden/nombre requieren importar de nuevo. No detecta automáticamente el preset activo de Arena.
- Recuperación automática tras un segundo de inactividad en `%LOCALAPPDATA%\ChaseLab_MM\recovery.chaselab`. Al iniciar se recupera en pausa y desconectado. Cambiar de proyecto conserva primero la recuperación actual.
- Sin exportación MOV, Factory avanzado ni otros efectos en esta demo.

La precisión temporal del reloj de escritorio y el consumo GPU requieren medición en Windows. Esta versión envía snapshots a 30 Hz y limita la lectura del efecto a 30 Hz, fuera del hilo de render; no se afirma igualdad de fluidez con la versión Mac.

## Actualizar o desinstalar

El instalador reemplaza la aplicación de esta demo en su carpeta habitual. Para actualizar Player, cierra Arena y usa de nuevo **Instalar Player…**. El instalador no cambia complementos de terceros.

Desinstala desde Configuración → Aplicaciones o el acceso **Desinstalar ChaseLab_MM Windows Demo**. Se conservan proyectos y recuperación. Para retirar también el efecto, cierra Arena y elimina `CLPlayerWinDemo_MM.dll` de la carpeta Extra Effects donde lo instalaste; las copias anteriores están en `%LOCALAPPDATA%\ChaseLab_MM\plugin-backups`.

## Compilar

El workflow `.github/workflows/windows-demo.yml` compila en `windows-2022`, ejecuta comprobaciones de compatibilidad/temporización, publica una aplicación .NET 8 autónoma, compila FFGL con Visual C++ y genera el instalador con Inno Setup. El resultado se descarga desde Actions → Windows demo → Artifacts.

Dependencias C++: SDK FFGL incluido, GLEW y nlohmann/json mediante vcpkg fijado a un commit. Incluye sus avisos de licencia. Código propio Apache-2.0; SDK FFGL BSD-3-Clause. No se incluye código de Chaser original.
