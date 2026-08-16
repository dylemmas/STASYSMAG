"""Quick test to verify SVG target rendering works."""
import sys
from pathlib import Path
from PyQt6.QtWidgets import QApplication
from PyQt6.QtCore import QRectF
from PyQt6.QtSvg import QSvgRenderer

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from stasys_app.base import TARGET_SPECS

def test_svg_files_exist():
    """Verify all SVG files are accessible."""
    base_dir = Path(__file__).parent.parent / 'stasys_app' / 'image_assets'

    for key, spec in TARGET_SPECS.items():
        svg_path = base_dir / spec.svg_filename
        assert svg_path.exists(), f"SVG not found: {svg_path}"
        print(f"[OK] {key}: {spec.svg_filename} found")

def test_svg_renderer_valid():
    """Verify QSvgRenderer can load each SVG."""
    app = QApplication.instance() or QApplication([])

    base_dir = Path(__file__).parent.parent / 'stasys_app' / 'image_assets'

    for key, spec in TARGET_SPECS.items():
        svg_path = base_dir / spec.svg_filename
        renderer = QSvgRenderer(str(svg_path))
        assert renderer.isValid(), f"Invalid SVG: {svg_path}"
        print(f"[OK] {key}: SVG renderer valid")

def test_issf_scoring():
    """Verify ISSF scoring with new target types."""
    from stasys_app.base import calculate_issf_score

    # Test center hit on 10m
    score, ring = calculate_issf_score(0, 0, TARGET_SPECS['10m_air_pistol'])
    assert score == 10.9 and ring == 10, f"Expected (10.9, 10), got ({score}, {ring})"
    print(f"[OK] 10m center hit: {score}, ring {ring}")

    # Test center hit on 20m
    score, ring = calculate_issf_score(0, 0, TARGET_SPECS['20m_pistol'])
    assert score == 10.9 and ring == 10, f"Expected (10.9, 10), got ({score}, {ring})"
    print(f"[OK] 20m center hit: {score}, ring {ring}")

    # Test miss
    score, ring = calculate_issf_score(50, 0, TARGET_SPECS['10m_air_pistol'])
    assert score == 0.0 and ring == 0, f"Expected (0.0, 0), got ({score}, {ring})"
    print(f"[OK] 10m miss: {score}, ring {ring}")

if __name__ == '__main__':
    print("Testing SVG integration...\n")
    test_svg_files_exist()
    print()
    test_svg_renderer_valid()
    print()
    test_issf_scoring()
    print("\n[OK] All tests passed!")
