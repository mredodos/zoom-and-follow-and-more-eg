# TODO: Advanced Source Transformation Mapping

## Problema Attuale

Quando una source in OBS non è adattata allo schermo (non ha CTRL+F applicato), il comportamento dello zoom e del follow del mouse può essere impreciso o causare ridimensionamenti inaspettati della source.

### Descrizione Tecnica

Il problema deriva da una limitazione nell'approccio attuale del mapping mouse-to-crop:

1. **Il crop filter lavora sulle dimensioni native della source** (es. 2560x1440)
2. **Il mouse si muove nello spazio dello schermo** (es. 1920x1080)
3. **Se la source non è adattata**, le dimensioni visualizzate nella scena differiscono da quelle native
4. **Il mapping mouse → crop diventa complesso** perché dobbiamo considerare:
   - Scale del scene item (`obs_sceneitem_get_scale()`)
   - Crop del scene item (`obs_sceneitem_get_crop()`)
   - Posizione del scene item nella scena (`obs_sceneitem_get_pos()`)
   - Bounds del scene item (`obs_sceneitem_get_bounds()`)
   - Come la source è visualizzata rispetto allo schermo/canvas di OBS

### Comportamento Attuale

- **Con CTRL+F (source adattata)**: Funziona perfettamente perché `displayed_width ≈ screen_width`
- **Senza CTRL+F (source non adattata)**: 
  - Lo script mostra un warning
  - Lo zoom funziona ma con precisione ridotta
  - Il mapping può essere impreciso quando la source è scalata/ritagliata manualmente

## Soluzione Proposta (Opzione 3)

Implementare una logica di mapping più avanzata che considera tutte le trasformazioni del scene item e calcola correttamente il mapping mouse-to-source anche quando la source non è adattata allo schermo.

### Approccio Tecnico

#### 1. Ottenere tutte le trasformazioni del scene item

```lua
-- Get scene item transformations
local scale = obs.obs_sceneitem_get_scale(scene_item)  -- {x, y}
local crop = obs.obs_sceneitem_get_crop(scene_item)     -- {left, top, right, bottom}
local pos = obs.obs_sceneitem_get_pos(scene_item)       -- {x, y}
local bounds = obs.obs_sceneitem_get_bounds(scene_item) -- {type, alignment, x, y}
local rotation = obs.obs_sceneitem_get_rot(scene_item)  -- rotation in degrees
local alignment = obs.obs_sceneitem_get_alignment(scene_item) -- alignment flags
```

#### 2. Calcolare le dimensioni visualizzate effettive

```lua
-- Calculate effective displayed dimensions
local displayed_width = (source_width - crop.left - crop.right) * scale.x
local displayed_height = (source_height - crop.top - crop.bottom) * scale.y
```

#### 3. Ottenere le dimensioni del canvas/scene

```lua
-- Get canvas dimensions (scene output size)
local canvas_width = obs.obs_video_info().base_width
local canvas_height = obs.obs_video_info().base_height
```

#### 4. Calcolare la posizione e le dimensioni del scene item nel canvas

```lua
-- Calculate scene item position and size in canvas space
-- This requires understanding:
-- - How OBS positions scene items (pos, bounds, alignment)
-- - How the scene item is displayed relative to the canvas
-- - Whether the scene item is cropped/scaled within the canvas
```

#### 5. Mappare le coordinate del mouse dal canvas alla source

```lua
-- Map mouse coordinates from canvas space to source native space
-- This is the critical step that needs to account for:
-- 1. Mouse position relative to canvas
-- 2. Scene item position in canvas
-- 3. Scene item scale and crop
-- 4. Scene item rotation (if applicable)
-- 5. Canvas-to-source coordinate transformation
```

### Algoritmo Proposto

```
1. Get mouse position in screen coordinates (already done)
2. Convert screen coordinates to canvas coordinates
   - Consider monitor layout and OBS canvas position
3. Check if mouse is within the scene item's displayed area in canvas
4. If yes, calculate relative position within scene item (0.0 to 1.0)
5. Map relative position to source native coordinates:
   - account for scene item crop
   - account for scene item scale
   - account for scene item position/alignment
6. Use mapped coordinates for crop calculation
```

### Funzioni da Implementare

1. **`get_canvas_dimensions()`**
   - Ottiene le dimensioni del canvas di OBS
   - Restituisce `{width, height}`

2. **`get_scene_item_canvas_bounds(scene_item)`**
   - Calcola i bounds del scene item nello spazio del canvas
   - Considera pos, scale, crop, bounds, alignment
   - Restituisce `{x, y, width, height}` in coordinate canvas

3. **`map_mouse_to_canvas(mouse_x, mouse_y, monitor)`**
   - Mappa le coordinate del mouse dallo schermo al canvas di OBS
   - Considera la posizione del canvas rispetto al monitor
   - Restituisce `{x, y}` in coordinate canvas

4. **`map_canvas_to_source(canvas_x, canvas_y, scene_item, source_width, source_height)`**
   - Mappa le coordinate dal canvas alle coordinate native della source
   - Considera tutte le trasformazioni del scene item
   - Restituisce `{x, y}` in coordinate source native

5. **`get_target_crop_advanced(mouse_x, mouse_y, current_zoom)`**
   - Versione avanzata di `get_target_crop()` che usa il nuovo sistema di mapping
   - Sostituisce la logica attuale con il nuovo algoritmo

### Considerazioni Importanti

#### Limitazioni OBS API

- L'API OBS Lua potrebbe non esporre direttamente le informazioni sul canvas
- Potrebbe essere necessario calcolare la posizione del canvas basandosi su informazioni del monitor
- La rotazione del scene item complica ulteriormente il mapping

#### Performance

- Il calcolo avanzato potrebbe essere più costoso in termini di performance
- Considerare caching dei valori che cambiano raramente (canvas dimensions, scene item bounds)
- Valutare se il calcolo può essere ottimizzato

#### Edge Cases

- Scene item parzialmente fuori dal canvas
- Scene item con bounds type diverso (stretch, scale, crop)
- Scene item ruotato
- Multi-monitor con canvas su monitor secondario
- Scene item in scene annidate

### Testing

Quando implementata, testare:

1. **Source adattata (CTRL+F)**: Deve funzionare come prima (backward compatibility)
2. **Source non adattata, scalata manualmente**: Zoom deve seguire correttamente il mouse
3. **Source non adattata, ritagliata manualmente**: Crop deve essere calcolato correttamente
4. **Source non adattata, scalata E ritagliata**: Combinazione di entrambi
5. **Source ruotata**: Se supportato, deve funzionare correttamente
6. **Multi-monitor**: Deve funzionare su tutti i monitor
7. **Scene annidate**: Deve gestire correttamente le scene dentro altre scene

### Documentazione da Consultare

- OBS Studio Lua API Documentation
- `obs_sceneitem_get_*` functions
- `obs_video_info()` structure
- Scene item transformation matrix (se disponibile)
- Canvas coordinate system in OBS

### Priorità

**Bassa** - La soluzione attuale (Opzione 1 + 2) è sufficiente per la maggior parte degli utenti. Questa implementazione è per utenti avanzati che vogliono usare lo zoom senza dover adattare la source allo schermo.

### Note

- Questa è una funzionalità avanzata che richiede una comprensione approfondita del sistema di coordinate di OBS
- Potrebbe richiedere test estensivi su diverse configurazioni
- Considerare di renderla opzionale (setting "Advanced Mapping Mode") per non impattare gli utenti che usano CTRL+F

