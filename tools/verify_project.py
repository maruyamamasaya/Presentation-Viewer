"""Check project structure on hosts without Xcode; does not compile Swift."""
from pathlib import Path
import re
import plistlib
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def parse_openstep(text):
    text = re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)
    tokens = re.findall(r'"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+', text)
    position = 0

    def take(expected=None):
        nonlocal position
        assert position < len(tokens), "Unexpected end of project"
        token = tokens[position]
        position += 1
        if expected is not None:
            assert token == expected, f"Expected {expected}, found {token}"
        return token

    def value():
        token = take()
        if token == "{":
            result = {}
            while tokens[position] != "}":
                key = take().strip('"')
                assert key not in result, f"Duplicate key {key}"
                take("=")
                result[key] = value()
                take(";")
            take("}")
            return result
        if token == "(":
            result = []
            while tokens[position] != ")":
                result.append(value())
                if tokens[position] != ")":
                    take(",")
            take(")")
            return result
        return token.strip('"')

    result = value()
    assert position == len(tokens), "Trailing tokens"
    return result


def verify():
    project = parse_openstep((ROOT / "PresentationViewer.xcodeproj/project.pbxproj").read_text(encoding="utf-8"))
    objects = project["objects"]
    assert objects[project["rootObject"]]["isa"] == "PBXProject"

    def references(value):
        if isinstance(value, dict):
            for child in value.values():
                references(child)
        elif isinstance(value, list):
            for child in value:
                references(child)
        elif re.fullmatch(r"[0-9A-F]{24}", value):
            assert value in objects, f"Missing object {value}"

    references(project)
    source_refs = {key: obj["path"] for key, obj in objects.items()
                   if obj["isa"] == "PBXFileReference" and obj.get("lastKnownFileType") == "sourcecode.swift"}
    for source in source_refs.values():
        assert (ROOT / source).is_file(), f"Missing Swift source {source}"
    actual_sources = {p.relative_to(ROOT).as_posix() for folder in ["PresentationViewer", "PresentationViewerTests"]
                      for p in (ROOT / folder).rglob("*.swift")}
    assert set(source_refs.values()) == actual_sources, "Swift file absent from project or stale reference"
    built = []
    for obj in objects.values():
        if obj["isa"] == "PBXSourcesBuildPhase":
            built.extend(objects[item]["fileRef"] for item in obj["files"])
    assert set(built) == set(source_refs) and len(built) == len(source_refs), "Missing or duplicate compile source"
    targets = {key: obj for key, obj in objects.items() if obj["isa"] == "PBXNativeTarget"}
    assert {obj["name"] for obj in targets.values()} == {"PresentationViewer", "PresentationViewerTests"}
    for obj in objects.values():
        if obj["isa"] == "XCBuildConfiguration":
            settings = obj["buildSettings"]
            if "IPHONEOS_DEPLOYMENT_TARGET" in settings:
                assert settings["IPHONEOS_DEPLOYMENT_TARGET"] == "17.0"
            if settings.get("PRODUCT_BUNDLE_IDENTIFIER") == "com.example.PresentationViewer":
                assert settings["TARGETED_DEVICE_FAMILY"] == "1,2"
                assert settings["INFOPLIST_FILE"] == "PresentationViewer/Info.plist"
                assert "LandscapeLeft" in settings["INFOPLIST_KEY_UISupportedInterfaceOrientations"]
                assert "LandscapeRight" in settings["INFOPLIST_KEY_UISupportedInterfaceOrientations"]
    info = plistlib.loads((ROOT / "PresentationViewer/Info.plist").read_bytes())
    assert info["UIRequiresFullScreen"] is False
    assert set(info["UISupportedInterfaceOrientations~ipad"]) == {
        "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
        "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"}
    manifest = info["UIApplicationSceneManifest"]
    assert manifest["UIApplicationSupportsMultipleScenes"] is False
    external = manifest["UISceneConfigurations"]["UIWindowSceneSessionRoleExternalDisplayNonInteractive"]
    assert external[0]["UISceneDelegateClassName"] == "$(PRODUCT_MODULE_NAME).ExternalDisplaySceneDelegate"
    for obj in objects.values():
        if obj["isa"] == "XCBuildConfiguration" and obj["buildSettings"].get("PRODUCT_BUNDLE_IDENTIFIER") == "com.example.PresentationViewer":
            assert obj["buildSettings"]["INFOPLIST_KEY_UIApplicationSceneManifest_Generation"] == "NO"
    scheme = ET.parse(ROOT / "PresentationViewer.xcodeproj/xcshareddata/xcschemes/PresentationViewer.xcscheme")
    for buildable in scheme.findall(".//BuildableReference"):
        assert buildable.attrib["BlueprintIdentifier"] in targets
    assert len(scheme.findall(".//TestableReference")) == 1
    assert not any(obj["isa"] in {"XCRemoteSwiftPackageReference", "XCSwiftPackageProductDependency"}
                   for obj in objects.values()), "Unexpected package dependency"
    print(f"PASS: OpenStep project syntax; {len(objects)} objects and references")
    print(f"PASS: {len(actual_sources)} Swift files exist and are compiled exactly once")
    print("PASS: app and XCTest targets; shared scheme; iOS 17; iPhone/iPad orientations; multitasking; no packages")
    print("NOT RUN: Swift compilation, XCTest, Simulator, iCloud and device validation")


if __name__ == "__main__":
    verify()
