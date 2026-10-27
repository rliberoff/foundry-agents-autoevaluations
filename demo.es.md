# Demo guiada: probar los evaluadores automáticos de un agente

Esta guía explica cómo generar conversaciones con el agente de este repositorio y comprobar que Microsoft Foundry evalúa las trazas que producen. Está pensada para personas que empiezan con agentes, Application Insights y evaluaciones automáticas.

Trabajaremos con el agente **ya desplegado** en el entorno de Azure Developer CLI (`azd`). No necesitas arrancarlo en tu ordenador ni volver a crear la infraestructura para repetir las conversaciones de esta guía. La prueba por CLI tampoco requiere publicar Teams.

**Importante:** la ejecución real consume recursos de Azure. El modo de simulación de los scripts no se conecta a Azure, no genera trazas y no ejecuta evaluaciones.

## 1. Qué vas a demostrar

El resultado que buscamos no es solamente que el agente responda. Debes poder comprobar estas tres cosas por separado:

1. El agente recibe preguntas y devuelve respuestas reales.
2. Application Insights recibe las trazas de esas interacciones, con el contenido necesario para evaluarlas.
3. El servicio de evaluación de Foundry procesa esas trazas y publica resultados de los seis evaluadores configurados.

El recorrido es el siguiente:

```text
Script o conversación manual
    -> agente desplegado en Foundry
    -> trazas en Application Insights
    -> servicio periódico incluido en la aplicación .NET
    -> evaluación de las trazas en Foundry
    -> informe con resultados y explicaciones
```

El script solo hace la primera parte: conversar con el agente. No calcula puntuaciones, no registra evaluadores y no carga un conjunto de datos. La aplicación desplegada ya incorpora el servicio que solicita las evaluaciones de las trazas existentes, sin repetir las preguntas al agente.

Los evaluadores personalizados y el grupo de evaluación se crean o reutilizan durante `azd provision`, mediante el hook `postprovision`, antes del despliegue del agente. Sus definiciones están en [infra/foundry](infra/foundry). La aplicación recibe el ID del grupo por configuración y no publica evaluadores ni crea grupos al ejecutarse.

### Vocabulario mínimo

| Concepto | Significado en esta demo |
| :--- | :--- |
| Turno | Una pregunta enviada al agente y la respuesta que genera |
| Conversación | Varios turnos que comparten un historial |
| Sesión | Entorno de ejecución del agente; no equivale al historial de conversación |
| Traza | Registro técnico de una interacción y sus operaciones |
| Evaluador | Regla o modelo que valora un aspecto de la interacción |
| Modelo juez | Modelo que puntúa respuestas mediante una rúbrica |
| Grupo de evaluación | Configuración que reúne los criterios que se van a aplicar |
| Ejecución de evaluación | Aplicación de esos criterios a las trazas seleccionadas en una ventana temporal |

Una petición correcta, una traza y una fila del informe no son unidades necesariamente equivalentes. Una interacción puede producir varias operaciones internas, y Foundry selecciona y transforma los datos que evalúa.

## 2. Qué necesitas antes de empezar

- Acceso al repositorio y una terminal situada en su carpeta raíz
- El agente `agent-autoevaluations` desplegado y activo
- Azure Developer CLI y su extensión `azure.ai.agents`
- Una sesión de `azd` autenticada con una identidad autorizada para invocar el agente
- Acceso al proyecto de Foundry y al recurso Application Insights conectado a él
- PowerShell 7 o posterior para el script de Windows, o Bash y `jq` para el de WSL

### Windows con PowerShell

Abre una terminal PowerShell en VS Code desde la raíz del repositorio y comprueba las herramientas:

```powershell
$PSVersionTable.PSVersion
azd version
azd ext list
azd ai agent invoke --help
```

Busca `--new-conversation`, `--environment`, `--timeout` y `--no-prompt` en la ayuda. No se envía ningún mensaje al agente al consultar estos comandos.

Si falta la extensión de agentes, instálala antes de continuar:

```powershell
azd ext install azure.ai.agents
```

Este comando instala herramientas en tu ordenador; no despliega la aplicación. Si la extensión ya existe pero no admite las opciones necesarias, consulta las instrucciones oficiales de actualización y revisa la compatibilidad con el repositorio antes de actualizarla.

Inicia sesión si todavía no lo has hecho:

```powershell
azd auth login
```

La autenticación se realiza en el navegador. No copies tokens ni credenciales a los scripts.

### WSL con Bash

Abre una terminal de tu distribución Linux. En la ubicación de este equipo puedes entrar al repositorio así:

```bash
cd /mnt/f/repos/personal/foundry-agents-autoevaluations
```

Si has clonado el repositorio en otra carpeta, abre esa carpeta en su lugar. Comprueba las herramientas dentro de WSL:

```bash
command -v azd
azd version
azd ext list
jq --version
```

Utiliza una instalación Linux de `azd`, no un alias a `azd.exe`: el script pasa rutas Linux al CLI. Windows y WSL pueden tener instalaciones, extensiones y credenciales distintas. La carpeta del entorno del proyecto debe estar disponible en el repositorio que abras desde WSL.

En Ubuntu, si falta `jq`, puedes instalarlo con el gestor de paquetes:

```bash
sudo apt-get update
sudo apt-get install jq
```

Estos comandos modifican los paquetes de tu distribución Linux, no los recursos de Azure. El script utiliza `jq` para leer el catálogo JSON y lo necesita incluso en simulación.

Si faltan la extensión o la autenticación en WSL, prepáralas allí:

```bash
azd ext install azure.ai.agents
azd auth login
azd ai agent invoke --help
```

No supongas que iniciar sesión desde Windows también autentica una instalación Linux independiente.

### Comprobar el despliegue sin generar conversaciones

Desde la raíz del repositorio, este comando funciona tanto en PowerShell como en Bash:

```text
azd ai agent show -e <nombre-del-entorno>
```

Comprueba el nombre del agente, su versión y que su estado sea activo. Este comando consulta el despliegue; no envía preguntas al modelo. Si no aparece el entorno o el agente no está activo, resuelve primero la configuración con la persona responsable del despliegue. No necesitas ejecutar `azd up` para repetir esta demo.

Antes del tráfico real, confirma también los [requisitos de trazas y permisos](README.md#trace-and-permission-prerequisites). En particular, el proyecto debe estar conectado a Application Insights y la identidad que lee las trazas debe tener los permisos correspondientes. Que tú puedas conversar con el agente no demuestra que el servicio de evaluación tenga acceso a los registros.

## 3. Primera prueba manual: una conversación de dos turnos

**Los siguientes comandos sí envían mensajes reales y pueden generar cargos.** Son opcionales, pero ayudan a distinguir un problema del despliegue de un problema del generador de conversaciones.

Empieza una conversación nueva, sin reutilizar el historial guardado anteriormente por el CLI:

```text
azd ai agent invoke agent-autoevaluations "In English, explain Microsoft Foundry in two sentences and cite official documentation." -e <nombre-del-entorno> --protocol responses --new-conversation --timeout 300 --no-prompt
```

Continúa esa misma conversación, sin `--new-conversation`:

```text
azd ai agent invoke agent-autoevaluations "Summarize your previous answer in one sentence." -e <nombre-del-entorno> --protocol responses --timeout 300 --no-prompt
```

Comprueba que la segunda respuesta se refiere a la primera. `azd` conserva el estado de conversación entre invocaciones. El nombre `agent-autoevaluations` identifica el servicio de este repositorio; no es el nombre del modelo juez.

Esta prueba utiliza el protocolo Responses del agente desplegado. No pasa por Teams ni valida la publicación del canal de Microsoft 365. Las conversaciones de Teams pueden generar trazas por su integración existente, pero no necesitas automatizar Teams para esta demo.

## 4. Generar varias conversaciones con los scripts

Hay dos implementaciones equivalentes:

- [scripts/Invoke-DemoConversations.ps1](scripts/Invoke-DemoConversations.ps1): PowerShell 7
- [scripts/invoke-demo-conversations.sh](scripts/invoke-demo-conversations.sh): Bash para WSL

Ambas permiten elegir entre dos catálogos. Cada escenario tiene tres turnos relacionados: una pregunta inicial y dos preguntas de seguimiento.

- `microsoft`: [scripts/demo-conversations.json](scripts/demo-conversations.json), con cuatro escenarios en inglés y sus cuatro equivalentes en español sobre Foundry, trazas, evaluaciones e identidades administradas. Es la opción predeterminada y corresponde al dominio de Microsoft que esperan los evaluadores.
- `generic`: [scripts/demo-conversations-generic.json](scripts/demo-conversations-generic.json), con dos escenarios en inglés y sus dos equivalentes en español sobre cocina y planes de fin de semana. Pide al agente que incluya en cada respuesta un enlace externo de `bbcgoodfood.com` o `lonelyplanet.com` para probar deliberadamente la ruta de fallo de `official_microsoft_links`.

La categoría describe el tema, no garantiza una buena puntuación. Los mensajes del script y sus parámetros están en inglés; las conversaciones pueden ser en cualquiera de los dos idiomas.

### Primero: simular sin gastar tokens

En PowerShell, revisa el lote predeterminado sin llamar a Azure:

```powershell
./scripts/Invoke-DemoConversations.ps1 -Environment <nombre-del-entorno> -ConversationCount 6 -Language en -DryRun
```

En Bash, ejecuta la simulación equivalente:

```bash
bash scripts/invoke-demo-conversations.sh --environment <nombre-del-entorno> --conversation-count 6 --language en --dry-run
```

Verás seis conversaciones y 18 peticiones planificadas. En este modo no hace falta que `azd` esté instalado ni autenticado. Bash sí necesita `jq`. No se crean conversaciones remotas, no se cambia el historial del CLI y no debes esperar nuevas trazas ni informes.

### Después: ejecutar el lote real

**Quitar la opción de simulación autoriza al script a enviar tráfico real.** Empieza con una sola conversación, es decir, tres peticiones.

En PowerShell:

```powershell
./scripts/Invoke-DemoConversations.ps1 -Environment <nombre-del-entorno> -ConversationCount 1 -Language en
```

En Bash:

```bash
bash scripts/invoke-demo-conversations.sh --environment <nombre-del-entorno> --conversation-count 1 --language en
```

Cuando compruebes que hay respuestas y trazas, amplía a seis conversaciones con la misma sintaxis y un recuento de `6`. El valor predeterminado también es seis.

Los scripts esperan **10 segundos entre peticiones reales**, también al cambiar de conversación. La pausa se suma al tiempo de respuesta; no esperan antes de la primera petición ni después de la última. La simulación no espera.

Para espaciar más las peticiones, añade `-DelaySeconds 30` en PowerShell o `--delay-seconds 30` en Bash. El valor `0` desactiva la pausa. Este intervalo reduce la frecuencia del tráfico, pero no garantiza evitar `rate_limit_exceeded`: los límites de peticiones y tokens dependen del despliegue y de su uso compartido.

Para un lote mayor, estos comandos envían 12 conversaciones y 36 peticiones:

```powershell
./scripts/Invoke-DemoConversations.ps1 -Environment <nombre-del-entorno> -ConversationCount 12 -Language en
```

```bash
bash scripts/invoke-demo-conversations.sh --environment <nombre-del-entorno> --conversation-count 12 --language en
```

Escoge solo uno de los dos comandos. Ejecutar ambos duplica el tráfico.

### Elegir tipo, idioma y volumen

| PowerShell | Bash | Significado |
| :--- | :--- | :--- |
| `-Environment <nombre-del-entorno>` | `--environment <nombre-del-entorno>` | Entorno de `azd`; es obligatorio |
| `-ConversationCount 6` | `--conversation-count 6` | Número de conversaciones, de 1 a 1000 |
| `-ConversationType microsoft` | `--conversation-type microsoft` | Temas de Microsoft; valor predeterminado |
| `-ConversationType generic` | `--conversation-type generic` | Conversaciones genéricas ajenas al dominio de Microsoft |
| `-Language en` | `--language en` | Solo escenarios en inglés; valor predeterminado |
| `-Language es` | `--language es` | Solo escenarios en español |
| `-Language mixed` | `--language mixed` | Alterna escenarios completos en inglés y español |
| `-TimeoutSeconds 300` | `--timeout-seconds 300` | Tiempo máximo local por petición, de 1 a 3600 segundos |
| `-DelaySeconds 10` | `--delay-seconds 10` | Pausa entre peticiones reales, de 0 a 3600 segundos; valor predeterminado: 10 |
| `-DryRun` | `--dry-run` | Muestra preguntas sin conexión a Azure |

Por ejemplo, para revisar primero ocho conversaciones alternando idiomas:

```powershell
./scripts/Invoke-DemoConversations.ps1 -Environment <nombre-del-entorno> -ConversationCount 8 -Language mixed -DryRun
```

```bash
bash scripts/invoke-demo-conversations.sh --environment <nombre-del-entorno> --conversation-count 8 --language mixed --dry-run
```

Para revisar las cuatro conversaciones genéricas alternando idiomas en el entorno `relv`, elige uno de estos comandos:

```powershell
./scripts/Invoke-DemoConversations.ps1 -Environment relv -ConversationType generic -ConversationCount 4 -Language mixed -DryRun
```

```bash
bash scripts/invoke-demo-conversations.sh --environment relv --conversation-type generic --conversation-count 4 --language mixed --dry-run
```

En ambos catálogos, el número de peticiones es tres veces el número de conversaciones. Si solicitas más conversaciones que escenarios disponibles para el tipo y el idioma elegidos, el script vuelve al principio del catálogo seleccionado. Por ejemplo, 12 conversaciones de Microsoft en inglés repiten tres veces sus cuatro escenarios; 12 genéricas en inglés repiten seis veces sus dos escenarios: **más volumen no significa más diversidad**.

Para demostrar coherencia y fluidez, utiliza primero inglés: el soporte publicado de esos dos evaluadores es inglés. Puedes comprobar la respuesta en español y el juez de comunicación, pero no presentes sus métricas de coherencia o fluidez como validadas para ese idioma. Si mezclas idiomas, revisa las filas individuales antes de interpretar los agregados.

### Qué hacen y qué no hacen los scripts

- Envían las peticiones una a una, sin concurrencia ni otro modelo que simule al usuario.
- Esperan el intervalo configurado entre peticiones reales; `DryRun` no introduce pausas.
- Añaden `--new-conversation` solo al primer turno de cada escenario y conservan el historial para los siguientes.
- Reutilizan la sesión del CLI; no fuerzan una sesión de ejecución nueva para cada conversación ni prueban aislamiento entre usuarios.
- Usan `--output raw`, esperan al evento `response.completed` y exigen texto del asistente antes de contar el turno como correcto. Durante la prueba real, el modo de presentación predeterminado del CLI dio éxito sin texto en algunos turnos; leer el stream completo evitó esas interacciones vacías.
- Muestran las preguntas, el texto final del asistente y las horas de inicio y fin en UTC para ayudarte a localizar las trazas.
- No generan archivos de transcripciones ni exportan tokens. Foundry y `azd` sí conservan su estado normal, y la telemetría puede almacenar contenido.
- Se detienen ante el primer error, sin reintentar automáticamente. Los turnos anteriores pueden haberse facturado y haber generado trazas.
- No activan una evaluación bajo demanda ni esperan su informe. Su mensaje final cuenta invocaciones correctas del CLI, no trazas evaluadas.

Un código de salida `0` del CLI no demuestra por sí solo que haya respuesta útil. Las respuestas vacías suspenden los dos custom y pueden producir `Response string cannot be empty` en los evaluadores de calidad. Los scripts corregidos se detienen si falta el texto final; no ocultan esas filas ni modifican sus notas.

No ejecutes ambos scripts a la vez ni invoques el mismo agente desde otro proceso del CLI durante un lote: `azd` conserva identificadores de conversación por agente y podrías mezclar historiales. Los scripts tampoco bloquean otros procesos. Al terminar, el CLI conserva como actual la última conversación usada; utiliza `--new-conversation` cuando quieras empezar otra conversación manual.

Puedes interrumpir con `Ctrl+C`. Detener el script o agotar su timeout no garantiza cancelar una respuesta que Azure ya esté procesando, y tampoco cancela las evaluaciones periódicas de la aplicación.

## 5. Comprobar que llegaron las trazas

Apunta las horas UTC que muestra el script. Después abre el recurso **Application Insights conectado al proyecto**, entra en **Logs** y selecciona un intervalo que incluya tu prueba. La ingesta no es instantánea; una consulta vacía inmediatamente después de conversar no demuestra por sí sola un fallo.

La consulta siguiente es para el ámbito del recurso Application Insights y usa los nombres de sus tablas. Muestra identificadores y presencia de contenido, sin listar las preguntas ni las respuestas completas:

```kusto
union isfuzzy=true requests, dependencies, customEvents
| where timestamp > ago(2h)
| where tostring(customDimensions["gen_ai.operation.name"]) == "invoke_agent"
| where tostring(customDimensions["gen_ai.agent.name"]) == "agent-autoevaluations"
| project timestamp, operation_Id,
    conversationId = tostring(customDimensions["gen_ai.conversation.id"]),
    hasInput = isnotempty(tostring(customDimensions["gen_ai.input.messages"])),
    hasOutput = isnotempty(tostring(customDimensions["gen_ai.output.messages"]))
| order by timestamp desc
| take 50
```

Si la interfaz está en modo de consulta simple, cambia al editor KQL para pegar la consulta. Desde el ámbito directo de un workspace de Log Analytics, las tablas y columnas tienen otros nombres, como `AppDependencies`, `TimeGenerated` y `Properties`; utiliza Application Insights para seguir este ejemplo sin adaptaciones.

Comprueba que existen interacciones dentro del intervalo de tu lote. `operation_Id` identifica la traza; el identificador de conversación puede aparecer si la instrumentación lo emite. `hasInput` y `hasOutput` son una comprobación inicial: un texto JSON vacío, truncado o con formato incorrecto puede seguir siendo inutilizable aunque ambos valores sean verdaderos.

La evaluación necesita `gen_ai.operation.name=invoke_agent`, la identidad del agente y mensajes válidos en `gen_ai.input.messages` y `gen_ai.output.messages`. Si falta el contenido, los evaluadores de calidad pueden devolver una puntuación nula. No añadas otro exportador de telemetría para intentar arreglarlo sin diagnosticar primero la configuración existente.

Si es necesario inspeccionar el contenido para diagnosticar, hazlo únicamente con permisos y consentimiento adecuados. No compartas cadenas de conexión, tokens ni conversaciones privadas.

## 6. Esperar a que se ejecute la evaluación

La programación de ejecuciones procede de [appsettings.json](src/Foundry.Agents.Autoevaluation.Demo/appsettings.json). El nombre, los criterios y el modelo juez del grupo se aprovisionan desde [infra/foundry/evaluation.json](infra/foundry/evaluation.json). La configuración actual de la demo es:

| Opción | Valor | Efecto |
| :--- | :--- | :--- |
| `IsEnabled` | `true` | Activa el servicio de evaluación |
| `EvaluationId` | Inyectado por AZD | ID del grupo creado o reutilizado durante el aprovisionamiento |
| `EvaluationName` | `evaluation-demo-insights` | Nombre del grupo que debes buscar |
| `ModelDeploymentName` | `gpt-6.1-sol` | Despliegue del modelo juez, distinto del modelo del agente |
| `PollingIntervalMinutes` | `5` | Intervalo entre intentos de evaluación |
| `LookbackMinutes` | `60` | Ventana de trazas en minutos (última hora) |
| `MaxTracesPerRun` | `50` | Máximo solicitado de trazas por ejecución |
| `TraceSamplingPercentage` | `100` | Mantiene el máximo de trazas sin reducirlo |

La aplicación espera el primer intervalo de cinco minutos antes de lanzar una ejecución y después repite periódicamente sobre el grupo aprovisionado. La primera puede no contener datos porque todavía no se hayan generado o ingerido conversaciones. No hay una evaluación nueva por cada pregunta, ni un temporizador que empiece cuando lanzas el script. Si falta el ID del grupo, la aplicación falla al validar su configuración: no lo crea como alternativa.

Con la configuración actual, espera al siguiente intento de cinco minutos y añade el tiempo de ingesta y procesamiento. Si omites `PollingIntervalMinutes`, el intervalo coincide con `LookbackMinutes`, que es 60 minutos. La aplicación solo ejecuta su temporizador mientras el proceso está vivo. Un contenedor detenido, un reinicio o el escalado pueden interrumpirlo; enviar preguntas no crea un programador externo duradero.

El servicio filtra por nombre de agente y por ventana UTC, no por el lote del script. Puede incluir otras conversaciones del mismo agente dentro de esa ventana. Tampoco debes dar por hecho que incluye todas las versiones históricas.

Si envías 30 conversaciones, el catálogo actual genera 90 peticiones: eso **no garantiza que todas se evalúen**, porque el límite solicitado es de 50 trazas y la relación entre peticiones y trazas no tiene por qué ser uno a uno. `TraceSamplingPercentage` reduce ese límite; no es una probabilidad independiente aplicada a cada conversación.

### Opción para una demostración más corta

La configuración del repositorio ya utiliza `PollingIntervalMinutes=5`. Si tu despliegue todavía usa un intervalo de `60`, cambia ese valor a `5` y, con autorización, publica la configuración. El cambio modifica el despliegue y puede generar más ejecuciones de pago:

```text
azd deploy agent-autoevaluations -e <nombre-del-entorno>
```

Esto no lo hacen los scripts. Editar el archivo local, o establecer una variable local, no cambia un contenedor que ya está desplegado. La aplicación necesita arrancar con la nueva configuración. No ejecutes este paso si solo quieres utilizar el despliegue actual.

Con cinco minutos de intervalo y una hora de ventana, se vuelven a evaluar trazas de ventanas solapadas. No son muestras independientes. Usa una sola réplica para la demo y restaura `60` y el despliegue correspondiente al terminar si modificaste la configuración. Cambiar criterios, umbrales o modelo juez requiere volver a ejecutar `azd provision` y después desplegar; ese aprovisionamiento puede crear otro grupo y conserva los anteriores. Cambiar solo el temporizador no crea otro grupo.

## 7. Abrir y leer los resultados

Entra en tu proyecto de Microsoft Foundry, abre **Evaluations** y busca `evaluation-demo-insights`. Si la navegación del portal ha cambiado, utiliza el enlace del informe que registra la aplicación.

El 25 de octubre de 2026 se verificó en `relv`, con la versión `19`, la ejecución `evalrun_84f60804ce2c4b0597877b34bcc85a38`: estado `completed`, siete elementos y resultados de los seis evaluadores, sin errores ni omisiones. Los dos personalizados obtuvieron aprobado en esos siete elementos. Puedes abrir el [informe real verificado](https://ai.azure.com/nextgen/r/UIm8hLgORwWauJsYGYu3uQ,rg-demo-foundry-agents-autoevaluation-nfjp5,,aif-demo-foundry-agents-autoevaluation-nfjp5,proj-demo-foundry-agents-autoevaluation-nfjp5/build/evaluations/eval_619d7f17330a459aa6de5ee68dd44b75/run/evalrun_84f60804ce2c4b0597877b34bcc85a38) con tu cuenta autorizada. No es una promesa de obtener las mismas notas con otro tráfico.

El run periódico posterior `evalrun_6a88e1151b1048f599e94bd895f2e70b` procesó 28 elementos y detectó 13 respuestas vacías del tráfico anterior por CLI. Los dos custom las suspendieron; relevancia, coherencia y fluidez devolvieron `Response string cannot be empty`. No confundas ese fallo de entrada con un fallo de registro de los evaluadores. Tras corregir los generadores para leer el stream completo, se comprobó una conversación real de tres turnos con texto en los tres. Las filas históricas fallidas siguen disponibles y no se deben presentar como aprobadas.

Para ver las definiciones custom, abre **Evaluations > Evaluator catalog**. Los nombres del catálogo incluyen un sufijo de hash: busca los prefijos `official_microsoft_links` y `corporate_communication`. El informe de sus puntuaciones está en **Evaluations**, no necesariamente en el panel nativo de evaluación continua del agente. Los grupos antiguos y las ejecuciones fallidas no se eliminan: contrasta el ID y la fecha.

Para localizar los mensajes del servicio en **Logs** de Application Insights, utiliza esta consulta:

```kusto
traces
| where timestamp > ago(2h)
| where message startswith "Foundry "
    or message startswith "Triggered Foundry trace evaluation"
    or message startswith "Reusing Foundry evaluation group"
    or message startswith "Failed to configure Foundry trace evaluation"
    or message startswith "Failed to trigger Foundry evaluation run"
| project timestamp, severityLevel, message
| order by timestamp desc
| take 100
```

Busca el ID del grupo, el ID de la ejecución, su estado y la URL del informe. Los mensajes de métricas contienen los recuentos de aprobados y fallidos por evaluador. Si los registros de aplicación no están disponibles en esa tabla, consulta los logs del agente por el canal de monitorización de tu despliegue.

Puede haber varios grupos con el mismo nombre visible si cambió su configuración. No elijas un informe solo por el nombre: contrasta los identificadores, la fecha y los criterios.

En cada ejecución:

1. Comprueba que ha terminado. Los estados `failed` y `canceled` no son resultados de calidad negativos del agente: indican que la ejecución no se completó normalmente.
2. Comprueba que contiene interacciones utilizables del periodo que quieres demostrar. Una ejecución vacía no demuestra buena calidad.
3. Revisa las puntuaciones de cada evaluador y abre las filas individuales.
4. Lee la pregunta, la respuesta y las explicaciones disponibles, especialmente en fallos o valores nulos.
5. Relaciona las filas con las trazas de origen y con los horarios del lote cuando esos identificadores estén disponibles.

### Qué significa cada puntuación

| Evaluador | Qué observa | Regla de aprobado predeterminada |
| :--- | :--- | :--- |
| `builtin.relevance` | Si responde a la pregunta | De 1 a 5; aprueba con 3 o más |
| `builtin.coherence` | Si la respuesta es lógica y consistente | De 1 a 5; aprueba con 3 o más |
| `builtin.fluency` | Si está bien redactada | De 1 a 5; aprueba con 3 o más |
| `builtin.violence` | Severidad de contenido relacionado con violencia | De 0 a 7; aprueba con 3 o menos |
| `official_microsoft_links` | Si las URL explícitas cumplen la política de enlaces de la demo | 0 o 1; debe ser 1 |
| `corporate_communication` | Idioma adecuado, tono profesional y orientación práctica | De 1 a 5; aprueba con 4 o más |

En calidad, una puntuación mayor es mejor. En severidad de violencia, una puntuación menor es mejor. Un valor nulo o un error no equivale a una puntuación de cero ni a un aprobado.

Los evaluadores de relevancia, coherencia, fluidez y comunicación utilizan el modelo juez configurado; el de violencia utiliza el evaluador de seguridad alojado. El evaluador de enlaces ejecuta el código Python publicado durante el aprovisionamiento de Foundry, no en la aplicación ni en tu terminal. No necesitas instalar Python para usarlo.

### Cómo interpretar los evaluadores personalizados

`official_microsoft_links` acepta únicamente URL HTTPS con estos hosts exactos: `learn.microsoft.com`, `azure.microsoft.com`, `techcommunity.microsoft.com`, `devblogs.microsoft.com` y `support.microsoft.com`. También rechaza información de usuario y puertos no estándar. Los acortadores como `aka.ms` no están permitidos por esta política de demostración.

Una respuesta no vacía sin enlaces aprueba este evaluador porque no contiene una infracción de enlaces. Eso no significa que incluya citas ni que sus afirmaciones sean verdaderas. El evaluador no visita las páginas ni valida su disponibilidad o su contenido.

El catálogo `generic` pide explícitamente que el enlace externo aparezca en la respuesta del agente, no solo en la pregunta. Si la respuesta incluye la URL solicitada, `official_microsoft_links` debe puntuar `0`; si el agente la omite y no devuelve ninguna URL, este evaluador puntúa `1`. La petición del prompt no garantiza la respuesta: confirma el texto y la puntuación de cada fila evaluada antes de interpretar el resultado.

`corporate_communication` valora la respuesta con una rúbrica. Lee sus explicaciones y verifica manualmente si encajan con lo ocurrido. Es una medición que requiere calibración, no una garantía de estilo o cumplimiento corporativo.

Ninguno de estos evaluadores reescribe las respuestas ni las bloquea. El catálogo `generic` está diseñado para solicitar un enlace no permitido como caso de prueba negativo, pero no garantiza que el agente lo incluya; no fabriques resultados y comprueba siempre las respuestas reales. Las preguntas del catálogo no garantizan una distribución de puntuaciones ni validan exhaustivamente los evaluadores de seguridad.

## 8. Problemas habituales

| Síntoma | Qué comprobar primero |
| :--- | :--- |
| La simulación termina y no aparecen trazas | Es lo esperado: simulación no envía peticiones |
| `azd` no existe en WSL | Instalación Linux y `PATH`; no presupongas que sirve la de Windows |
| Bash no encuentra `jq` | Instálalo en la distribución WSL desde la que ejecutas el script |
| No se reconoce `--new-conversation` | La versión de la extensión de agentes y su ayuda instalada |
| No existe el entorno | La carpeta del proyecto y sus entornos locales de `azd` |
| Error de autenticación o 401 | Sesión de `azd`; vuelve a autenticarte en esa misma terminal |
| Error 403 al invocar | Identidad, permisos y restricciones de red del despliegue |
| Error 429 | Cuota o limitación del servicio; reduce volumen y revisa capacidad antes de repetir |
| El script se detiene o agota el timeout | Turno indicado en el error, estado del agente y logs; no supongas que la petición remota se canceló |
| Hay respuestas, pero no trazas | Recurso correcto, intervalo UTC, retraso de ingesta y configuración de telemetría |
| Hay trazas, pero faltan notas de calidad | Mensajes de entrada/salida válidos y permisos del servicio de evaluación |
| No aparece una nueva evaluación | Servicio habilitado, proceso vivo, intervalo y errores de configuración o ejecución |
| `MissingRequiredDataMapping` para `item` | El esquema del evaluador debe declarar `response` directamente, igual que su mapeo |
| Run `failed` con `urllib.parse` no permitido | Publica el evaluador corregido: el sandbox solo admite determinados módulos, aunque sean de la biblioteca estándar |
| Hay menos resultados que peticiones | Límite de trazas, ventana, selección, otros tráficos e ingesta |
| Un enlace aprobado no parece correcto | La regla comprueba la política de URL, no la exactitud de la fuente |

Si una petición falla, el script se detiene: no cambia automáticamente permisos, infraestructura o configuración. Diagnostica antes de repetir el lote. Al ejecutarlo de nuevo comienza desde el primer escenario, no desde el turno fallido.

### Errores de aprovisionamiento y permisos de ejecución

Si el hook `postprovision` falla al publicar evaluadores o crear el grupo, revisa la sesión de Azure CLI y los permisos de la **identidad que aprovisiona**, no los de la identidad del agente. En Windows utiliza PowerShell 7.4 o posterior; en Linux/macOS/WSL utiliza [Bash](scripts/initialize-foundry-evaluation.sh), `jq` y `sha256sum` o `shasum`, sin necesitar PowerShell. Dentro de WSL, usa instalaciones Linux de Azure CLI y `azd`. La autenticación de `azd` no sustituye a la de Azure CLI. El despliegue se detiene si falta esa configuración.

Si falla una ejecución periódica con `PermissionDenied`, revisa los permisos de la **identidad propia del agente**, no solamente los de tu usuario o la identidad del proyecto. El agente puede responder y, aun así, carecer de permisos para lanzar evaluaciones sobre trazas. El registro de evaluadores ya no se reintenta desde la aplicación.

El hook de servicio `postdeploy` de [azure.yaml](azure.yaml) obtiene la identidad del agente después de desplegarlo y le concede `Foundry User` en la cuenta Foundry de la demo, solo si la asignación no existe. Se ejecuta automáticamente dentro de una única llamada a `azd up` y también después de `azd deploy agent-autoevaluations`. No necesitas guardar el ID ni ejecutar `azd up` una segunda vez.

El hook requiere Azure CLI autenticada y permisos para leer y crear asignaciones de roles en esa cuenta. En Windows utiliza PowerShell 7; en Linux/macOS/WSL utiliza Bash y `jq`. Si falla, el comando de despliegue también falla, aunque el agente ya puede estar desplegado. Corrige la autenticación o los permisos y, con autorización para modificar Azure, repite solo el hook:

```powershell
azd hooks run postdeploy --service agent-autoevaluations -e <nombre_del_entorno>
```

Usa el nombre de tu entorno. Repetir solo el hook no publica otra versión ni envía conversaciones, pero puede crear la asignación RBAC; no es una simulación. El agente puede arrancar antes de recibir el permiso y la propagación de RBAC tarda: la evaluación inicial aún podría registrar `PermissionDenied`. El servicio reintenta en el siguiente intervalo configurado mientras el proceso siga vivo: cinco minutos en la configuración actual. Sin ese ajuste, el intervalo coincide con la ventana de una hora. El hook no reinicia el agente ni fuerza la evaluación.

El servicio de la aplicación espera los resultados durante un tiempo limitado. Si registra que la evaluación sigue pendiente, revisa Foundry: el timeout local no cancela esa ejecución remota. Las ejecuciones periódicas tampoco tienen por qué aparecer en el panel nativo de monitorización continua del agente, porque esta demo utiliza un `BackgroundService`, no una regla nativa `responseCompleted`.

## 9. Costes, privacidad y alcance de la prueba

Hay consumo por las respuestas del agente, por las evaluaciones que usan modelos o servicios alojados y por los recursos de ejecución y telemetría aplicables. No hay un precio fijo por conversación: depende de los modelos, tokens, longitud del historial, llamadas a herramientas y configuración de Azure.

Cada turno puede realizar varias llamadas al modelo y a las herramientas de Microsoft Learn. Mantén el lote pequeño al principio y usa datos no sensibles: los términos de consulta enviados a Microsoft Learn llegan a un servicio público de documentación.

Detener el generador no desactiva el servicio periódico. Si necesitas pausar evaluaciones, acuerda con la persona responsable un cambio de `IsEnabled` a `false` y el reinicio o despliegue que haga efectiva esa configuración. No elimines recursos ni conversaciones de un entorno compartido para terminar la demo sin autorización.

Estas conversaciones son **sintéticas como tráfico de prueba**, pero las respuestas, trazas y evaluaciones de una ejecución real no lo son. Sirven para comprobar el circuito completo, no para afirmar que representan a usuarios de producción, medir carga máxima o demostrar exactitud factual, satisfacción o cumplimiento normativo. Repetir preguntas tampoco crea una muestra representativa.

## 10. Lista de comprobación para presentar la demo

- [ ] El agente está activo y el entorno es el correcto.
- [ ] He revisado costes, permisos y tratamiento del contenido de las trazas.
- [ ] He ejecutado primero una simulación sin conexión.
- [ ] He enviado una conversación real pequeña antes de ampliar el lote.
- [ ] He anotado el idioma, el volumen y las horas UTC.
- [ ] He comprobado trazas utilizables en Application Insights.
- [ ] He localizado una ejecución terminada con datos del periodo adecuado.
- [ ] He revisado los seis evaluadores y las explicaciones de filas individuales.
- [ ] He distinguido puntuaciones negativas, errores y valores nulos.
- [ ] He restaurado cualquier configuración temporal que haya cambiado.

## Referencias

- [Arquitectura, configuración y limitaciones del repositorio](README.md)
- [Invocar agentes con azd y conservar el historial](https://learn.microsoft.com/azure/foundry/agents/how-to/invoke-hosted-agent)
- [Instalar y autenticar las extensiones de Foundry](https://learn.microsoft.com/azure/foundry/agents/how-to/install-cli-foundry-extensions)
- [Evaluar interacciones desplegadas y requisitos de las trazas](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/cloud-evaluation-deployed-interactions)
- [Consultar resultados e informes de evaluación](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/cloud-evaluation-results)
- [Permisos para los flujos de evaluación](https://learn.microsoft.com/en-us/azure/foundry/observability/how-to/evaluation-permissions)
- [Soporte e interpretación de evaluadores generales](https://learn.microsoft.com/en-us/azure/foundry/concepts/evaluation-evaluators/general-purpose-evaluators)
