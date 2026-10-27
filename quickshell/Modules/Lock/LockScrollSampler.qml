pragma ComponentBehavior: Bound

import QtQuick
import qs.Common
import qs.Services
import "../../Common/WidgetPlacement.js" as Placement
import "../../Common/LockScrollAtlas.js" as Atlas

Item {
    id: root

    required property var screen
    required property string source
    required property real imageWidth
    required property real imageHeight

    readonly property string screenName: screen.name
    readonly property string backgroundKey: LockPlacementService.backgroundKey(screenName, screen.width, screen.height)
    readonly property bool needed: !IdleService.isShellLocked && imageWidth > 0 && imageHeight > 0 && LockPlacementService.usesScrollAtlas(screenName) && LockPlacementService.neededFor(screen) && !LockPlacementService.hasSample(screenName, backgroundKey)
    readonly property real sampleScale: LockPlacementService.sampleSize / Math.max(1, screen.width, screen.height)
    readonly property int sampleWidth: Math.max(1, Math.round(screen.width * sampleScale))
    readonly property int sampleHeight: Math.max(1, Math.round(screen.height * sampleScale))
    readonly property var atlasSize: Atlas.atlasSize(imageWidth, imageHeight, screen.width, screen.height, sampleWidth, sampleHeight)
    readonly property string atlasKey: JSON.stringify([source, atlasSize.width, atlasSize.height, Theme.lockScreenScrimAlpha, Theme.screenOffColor.toString(), SettingsData.effectiveWallpaperBackgroundColor.toString()])
    property var atlas: null
    readonly property bool busy: builder.active

    onNeededChanged: sample()
    onBackgroundKeyChanged: sample()
    Component.onCompleted: LockPlacementService.setScrollSampler(screenName, true)
    Component.onDestruction: LockPlacementService.setScrollSampler(screenName, false)

    function sample() {
        if (!needed || busy)
            return;
        if (atlas?.key !== atlasKey) {
            builder.active = true;
            return;
        }
        if (atlas.failed)
            return;
        const scroll = SessionData.getMonitorScrollPosition(screenName);
        const view = Atlas.scrollWindow(imageWidth, imageHeight, screen.width, screen.height, scroll.scrollX, scroll.scrollY);
        LockPlacementService.storeSample(screenName, backgroundKey, Atlas.crop(atlas.luminances, atlas.width, atlas.height, view, sampleWidth, sampleHeight), sampleWidth, sampleHeight);
    }

    function finish(result) {
        atlas = result;
        Qt.callLater(() => {
            builder.active = false;
            sample();
        });
    }

    Loader {
        id: builder
        active: false

        sourceComponent: Canvas {
            property string key
            property string imageUrl

            opacity: 0

            function load() {
                if (available && imageUrl)
                    loadImage(imageUrl, Qt.size(width, height));
            }

            Component.onCompleted: {
                key = root.atlasKey;
                imageUrl = root.source;
                width = root.atlasSize.width;
                height = root.atlasSize.height;
                load();
            }
            onAvailableChanged: load()
            onImageLoaded: requestPaint()
            onPaint: {
                if (isImageError(imageUrl)) {
                    root.finish({
                        key,
                        failed: true
                    });
                    return;
                }
                if (!isImageLoaded(imageUrl))
                    return;
                const context = getContext("2d");
                context.fillStyle = SettingsData.effectiveWallpaperBackgroundColor;
                context.fillRect(0, 0, width, height);
                context.drawImage(imageUrl, 0, 0, width, height);
                const pixels = context.getImageData(0, 0, width, height).data;
                unloadImage(imageUrl);
                const scrim = Theme.screenOffColor;
                const alpha = Theme.lockScreenScrimAlpha;
                const blend = (value, over) => value / 255 * (1 - alpha) + over * alpha;
                const luminances = new Array(width * height);
                for (let i = 0; i < luminances.length; i++)
                    luminances[i] = Placement.luminance(blend(pixels[i * 4], scrim.r), blend(pixels[i * 4 + 1], scrim.g), blend(pixels[i * 4 + 2], scrim.b));
                root.finish({
                    key,
                    width,
                    height,
                    luminances
                });
            }
        }
    }
}
