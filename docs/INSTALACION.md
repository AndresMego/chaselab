# Instalación y prueba de ChaseLab

## Paquetes

- AppleSilicon: editor arm64, para Mac con chip Apple.
- Intel-experimental: editor x86_64, para que un tester compruebe el funcionamiento en un Mac Intel real.
- Ambos incluyen los mismos seis efectos universales para Mac. No son versiones Windows.

Estos paquetes beta no tienen firma Developer ID ni notarización. El archivo .pkg instala ChaseLab.app en Aplicaciones. No instala efectos directamente dentro de la carpeta de otro usuario ni cierra Arena por la fuerza.

Guarda y cierra Arena y la copia anterior de ChaseLab Live. Instala el .pkg, abre ChaseLab desde Aplicaciones y usa el menú «Instalar efectos en Arena…». Selecciona la carpeta Extra Effects de tu Arena. Confirma el destino; las versiones previas de los mismos archivos se respaldan fuera de la carpeta de efectos. Abre Arena de nuevo y busca los nombres CL.

El nombre del editor es ChaseLab. Los nombres de los efectos son CL Player, CL Bumper, CL Outliner, CL Wiper y CL Random; la fuente es CL Outline Src. Sus identificadores FFGL y nombres de archivo se conservaron para que Arena reconozca las composiciones anteriores. No renombres archivos dentro de los bundles.

El editor debe estar abierto y conectado. CL Player y CL Wiper necesitan una secuencia con contenido; el primer ejemplo incluido ya lo tiene. En Wiper Auto anima Step; Random Auto usa su propio Speed. En Manual, Bumper/Wiper/Random responden a pulsaciones de Next.

## Protocolo para el tester Intel

1. Anotar modelo de Mac, macOS y versión de Arena; confirmar que el editor abre y que aparecen los seis complementos.
2. Abrir el ejemplo sintético, guardar/reabrir un proyecto y comprobar que se recupera la sesión.
3. Importar un XML de prueba propio; comprobar tamaño del montaje y selección de slices.
4. Probar grilla, dibujo/arrastre, copiar pasos, duración, zoom y mano con clic central; editar una envolvente.
5. Comprobar Player, cinco disparos Bumper, Outliner Pixel/Filled con Animate, Wiper Auto/Manual y Random Auto/Manual/Echoes, uno a la vez.
6. Guardar la composición de prueba, cerrar y reabrir Arena. Verificar nombres, parámetros y ausencia de efectos faltantes.
7. Actualizar el mismo paquete y comprobar que no aparecen duplicados ni se pierden proyectos. Registrar cualquier error y, si es posible, una captura sin datos privados.

Una compilación Intel correcta, o ejecutarla mediante Rosetta, no sustituye esta prueba en hardware Intel.

## Recuperación y retirada

Las copias de complementos reemplazados están en Application Support/ChaseLab-Installer/Backups dentro de tu usuario. Para recuperar una versión: cierra Arena y restaura solo los bundles de la copia elegida a su ubicación anterior. Guarda la versión actual antes de restaurar.

Para retirar ChaseLab, cierra el editor/Arena y elimina la app y únicamente sus seis bundles propios. Los datos de proyectos/recuperación y la biblioteca de envolventes se conservan; no se borran al quitar la app. No elimines la carpeta completa Extra Effects.
