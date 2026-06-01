# ISSF Target Integration Design Document

**Date**: 2025-06-01
**Author**: Claude (STASYS Project)
**Status**: Design Approved, Pending Implementation

---

## Context

The Shot Analysis tab currently displays shot traces over a simple 3-ring visualization. This design adds International Shooting Sport Federation (ISSF) standard target support with accurate scoring rings, proper target graphics, and decimal scoring (10.0-10.9) alongside the existing stability score system.

**Problem**: Users need to visualize shot impacts on standardized targets for realistic training analysis.

**Solution**: Extend `ShotTraceCanvas` with ISSF target rendering mode and dual scoring display (ISSF + Stability).

---

## Architecture Overview

### Modified Component

**File**: `stasys_app/base.py`
**Class**: `ShotTraceCanvas` (lines ~1276-1368)

The existing widget will be extended to support two rendering modes:
- **Simple Mode** (current): Basic concentric rings
- **ISSF Mode** (new): Full ISSF target with proper scoring rings

### New Components

1. **`ISSFTargetSpec`**: Data class for target dimensions
2. **`TARGET_SPECS`**: Dictionary of predefined ISSF configurations
3. **ISSF scoring calculator**: Function to convert impact position to decimal score
4. **Target renderer**: Drawing method for ISSF targets

---

## ISSF Target Specifications

### Target Types

| Target Type | Distance | Total Diameter | 10-Ring | 1-Ring | Rings |
|-------------|----------|-----------------|---------|--------|-------|
| 10m Air Pistol | 10m | 170mm | 11.5mm | 170mm | 10 |
| 25m Sport Pistol | 25m | 500mm | 50mm | 500mm | 10 |
| 50m Free Pistol | 50m | 500mm | 50mm | 500mm | 10 |

### Scoring Ring Colors (ISSF Standard)

- **Rings 10-8**: Black (bullseye area)
- **Rings 7-4**: Black (outer scoring zone)
- **Rings 3-1**: White (outer zone)
- **Background**: White

### Decimal Scoring

Each ring is divided into 10 sub-zones for decimal scoring:
- Inner edge: X.9 (e.g., 10.9)
- Outer edge: X.0 (e.g., 10.0)

---

## Data Structures

### Target Specification

```python
@dataclass
class ISSFTargetSpec:
    """ISSF target specification for rendering and scoring."""
    name: str                    # Display name
    distance_m: float           # Target distance in metres
    total_diameter_mm: float    # Outer edge diameter
    ten_ring_diameter_mm: float # 10-ring outer edge
    inner_ten_mm: float         # 10.9 ring diameter
    ring_count: int             # Number of scoring rings (10)
    ring_colors: List[Tuple[int, str]]  # (ring_number, color)
```

### Target Specifications Dictionary

```python
TARGET_SPECS = {
    '10m_air_pistol': ISSFTargetSpec(
        name='10m Air Pistol',
        distance_m=10.0,
        total_diameter_mm=170.0,
        ten_ring_diameter_mm=11.5,
        inner_ten_mm=5.75,
        ring_count=10,
        ring_colors=[...]
    ),
    '25m_sport_pistol': ISSFTargetSpec(...),
    '50m_free_pistol': ISSFTargetSpec(...),
}
```

---

## ShotTraceCanvas Extensions

### New Properties

```python
class ShotTraceCanvas(QWidget):
    def __init__(self, parent=None):
        # ... existing code ...
        self.target_type = '10m_air_pistol'  # Default
        self.issf_mode = True                 # Enable ISSF rendering
        self.impact_points = []               # List of (x, y, score) for overlay
```

### New Methods

#### `set_target_type(type_key: str)`
- Updates `self.target_type` from TARGET_SPECS
- Triggers canvas repaint
- Raises ValueError if key not found

#### `calculate_issf_score(impact_x_cm: float, impact_y_cm: float) -> Tuple[float, int]`
- Converts impact coordinates to radial distance from center
- Maps distance to scoring ring based on target specification
- Returns: (decimal_score, ring_number)
- Example: (10.4, 10) for edge of 10-ring

#### `draw_issf_target(painter: QPainter, scale: float, center: Tuple[int, int])`
- Renders full ISSF target graphic with:
  - Concentric scoring rings with proper colors
  - Ring numbers (optional, can be toggled)
  - Proper scaling based on canvas size
- Uses `QRadialGradient` for realistic appearance

#### `draw_impact_points(painter: QPainter, scale: float, center: Tuple[int, int])`
- Overlays shot impacts from history
- Color-codes by score (green for 10+, yellow for 8-9, red for <8)
- Shows 'X' for misses (outside target)

### Modified Methods

#### `paintEvent(event)`
```python
def paintEvent(self, event):
    painter = QPainter(self)
    painter.setRenderHint(QPainter.Antialiasing)
    painter.fillRect(self.rect(), QColor(COLORS['bg_secondary']))

    w, h = self.width(), self.height()
    cx, cy = w // 2, h // 2
    scale = min(w, h) / (2 * self.plot_range) * 0.9 * self.scale

    # NEW: ISSF or Simple target
    if self.issf_mode:
        self.draw_issf_target(painter, scale, (cx, cy))
    else:
        # Existing simple ring drawing
        for r in self.ring_radii:
            # ... existing code ...

    # Existing trace drawing (unchanged)
    self._draw_path(painter, self.hol_x, self.hol_y, cx, cy, scale,
                    QPen(QColor(self.COL_HOLD), 2))
    # ... rest of existing code ...
```

#### `set_trace(...)` (Extended signature)
```python
def set_trace(self, hold=None, press=None, recoil=None, score=0,
              impact_x_cm=0.0, impact_y_cm=0.0, shot_idx=0,
              target_type='10m_air_pistol'):  # NEW parameter
    self.target_type = target_type
    # ... existing code ...
```

---

## ISSF Scoring Calculation

### Algorithm

```python
def calculate_issf_score(impact_x_cm: float, impact_y_cm: float,
                        target_spec: ISSFTargetSpec) -> Tuple[float, int]:
    """
    Convert impact position to ISSF decimal score.

    Args:
        impact_x_cm: X offset from center (cm)
        impact_y_cm: Y offset from center (cm)
        target_spec: Target specification

    Returns:
        (decimal_score, ring_number)
        Examples: (10.9, 10) for center, (8.5, 8), (0.0, 0) for miss
    """
    # Calculate radial distance from center
    distance_mm = math.sqrt(impact_x_cm**2 + impact_y_cm**2) * 10

    # Check for miss (outside target)
    if distance_mm > target_spec.total_diameter_mm / 2:
        return (0.0, 0)

    # Determine ring number (1-10)
    ring_spacing = (target_spec.total_diameter_mm -
                    target_spec.ten_ring_diameter_mm) / (target_spec.ring_count - 1)

    if distance_mm <= target_spec.inner_ten_mm:
        ring = 10
        # Calculate decimal within 10-ring
        decimal = 10.0 + (1.0 - (distance_mm / target_spec.inner_ten_mm))
    else:
        ring = int(10 - (distance_mm - target_spec.ten_ring_diameter_mm/2) / ring_spacing)
        ring = max(1, min(10, ring))
        decimal = float(ring)

    return (round(decimal, 1), ring)
```

---

## UI Integration

### Settings Tab Changes

Add new controls to `_build_settings_tab()`:

```python
# Target Type Dropdown
target_type_label = QLabel("Target Type:")
self.cmb_target_type = QComboBox()
self.cmb_target_type.addItems([
    "10m Air Pistol",
    "25m Sport Pistol",
    "50m Free Pistol"
])
self.cmb_target_type.currentTextChanged.connect(self.change_target_type)

# Target View Mode
view_mode_label = QLabel("Target View:")
self.cmb_view_mode = QComboBox()
self.cmb_view_mode.addItems(["ISSF Target", "Simple Rings"])
self.cmb_view_mode.currentTextChanged.connect(self.change_view_mode)
```

### Shot Analysis Tab Changes

#### PerShotStatsWidget Extensions

Modify `_setup_ui()` to add ISSF score display:

```python
# After existing score displays
self._issf_score_lbl = QLabel("ISSF: --")
self._issf_score_lbl.setStyleSheet(f"color: {COLORS['text_secondary']}; font-size: 12px;")
layout.addWidget(self._issf_score_lbl)
```

Modify `populate()` to calculate and display ISSF score:

```python
def populate(self, shot):
    # ... existing code ...

    # NEW: Calculate and display ISSF score
    ix = shot.get('impact_x_cm', 0) or 0
    iy = shot.get('impact_y_cm', 0) or 0
    target_spec = TARGET_SPECS[self.parent().target_type]
    issf_score, ring = calculate_issf_score(ix, iy, target_spec)
    self._issf_score_lbl.setText(f"ISSF: {issf_score:.1f}")
```

### Database Schema Extension (Optional)

Add columns to `shot_traces` table:

```sql
ALTER TABLE shot_traces ADD COLUMN issf_score REAL;
ALTER TABLE shot_traces ADD COLUMN issf_ring INTEGER;
ALTER TABLE shot_traces ADD COLUMN target_type TEXT DEFAULT '10m_air_pistol';
```

---

## Configuration

### Settings JSON Structure

Update `stasys_app/settings.json`:

```json
{
    "existing_settings": "...",
    "target_type": "10m_air_pistol",
    "target_view_mode": "issf",
    "target_distance_override": null
}
```

### Default Configuration

- **First launch**: 10m Air Pistol with ISSF mode enabled
- **Existing users**: Keep simple rings, show prompt to enable ISSF
- **Migration**: On first run after update, detect if settings.json exists

---

## Error Handling

### Invalid Impact Points

- Shots outside target area: Score as 0 (miss)
- Visual: Red 'X' marker at impact location

### Target Distance Mismatch

- If actual distance ≠ configured distance: Display warning banner
- Allow manual override in Settings

### Missing Configuration

- Invalid `target_type` key: Default to 10m Air Pistol
- Log warning but don't crash

### Rendering Errors

- Invalid scale factors: Clamp to safe range
- Missing colors: Use fallback from COLORS dict

---

## Testing Strategy

### Unit Tests (Optional)

Add to `test/test_issf_target.py`:

```python
def test_issf_scoring():
    """Test score calculation for known positions."""
    spec = TARGET_SPECS['10m_air_pistol']
    assert calculate_issf_score(0, 0, spec) == (10.9, 10)  # Center
    assert calculate_issf_score(0.0575, 0, spec)[0] == 10.0  # Edge of 10-ring

def test_target_specs():
    """Validate ring dimensions match ISSF standards."""
    assert TARGET_SPECS['10m_air_pistol'].total_diameter_mm == 170.0

def test_impact_overlay():
    """Verify impact points render correctly."""
    canvas = ShotTraceCanvas()
    canvas.impact_points = [(0, 0, 10.9), (1.0, 1.0, 8.5)]
    # Verify render doesn't crash
```

### Manual Testing Checklist

1. [ ] All three target types render with correct ring sizes
2. [ ] Shot impacts overlay in correct positions
3. [ ] Target type switching works from Settings
4. [ ] ISSF score displays alongside stability score
5. [ ] Zoom/pan functions correctly with ISSF target
6. [ ] Shot trace phases still display over ISSF target
7. [ ] Misses (outside target) show 'X' marker
8. [ ] Target view mode toggle works (ISSF ↔ Simple)

---

## Implementation Verification

### End-to-End Test Steps

1. Launch STASYS application
2. Navigate to Settings tab
3. Set "Target Type: 10m Air Pistol"
4. Set "Target View Mode: ISSF Target"
5. Navigate to Shot Analysis tab
6. Verify ISSF target displays with proper rings and colors
7. Load a session with shot data
8. Verify impact points overlay on target
9. Verify ISSF score displays in Per-Shot Statistics
10. Switch target types (25m, 50m) and verify scaling

### Success Criteria

- [ ] ISSF target renders with accurate ring proportions
- [ ] Shot impacts overlay at correct positions
- [ ] ISSF decimal score calculates correctly (10.0-10.9)
- [ ] Both ISSF and stability scores display simultaneously
- [ ] Target type switching works without glitches
- [ ] Shot trace phases still render over ISSF target
- [ ] Configuration persists across sessions

---

## File Changes Summary

### Primary File

**`stasys_app/base.py`** (~250-300 new lines)

- Configuration section (~line 50): Add `ISSFTargetSpec`, `TARGET_SPECS`
- `ShotTraceCanvas` class (~line 1276): Extend with ISSF methods
- `PerShotStatsWidget` class (~line 1421): Add ISSF score display
- Settings tab build method: Add target controls

### Optional Files

- `test/test_issf_target.py`: Unit tests
- `stasys_app/settings.json`: Default configuration

---

## Implementation Order

1. Add `ISSFTargetSpec` dataclass and `TARGET_SPECS` dictionary
2. Implement `calculate_issf_score()` function
3. Extend `ShotTraceCanvas` with new properties
4. Implement `draw_issf_target()` method
5. Modify `paintEvent()` to support ISSF mode
6. Extend `PerShotStatsWidget` with ISSF score display
7. Add Settings tab controls for target configuration
8. Wire up target type switching logic
9. Add persistence to settings.json
10. Test and verify

---

## References

- ISSF Official Rules: https://www.issf-sports.org/
- 10m Air Pistol Target Specification: ISSF Technical Rules 6.3
- Existing STASYS scoring system: [base.py:992-1067](d:\BASEFW\STASYSESP32\stasys_app\base.py#L992-L1067)
