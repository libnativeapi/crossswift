package dev.crossswiftui.android

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Choreographer
import androidx.annotation.Keep
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.requiredHeight
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Fill
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.hideFromAccessibility
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Presents one Swift renderer inside a bounded Compose layout with dual Android/iOS styling. */
@Keep
class SwiftUIComposeHost(
    private var handle: Long,
    initialStyle: AndroidUIStyle = AndroidUIStyle.ANDROID_NATIVE,
    private val showStyleSwitcher: Boolean = false,
    private val onOpenURL: ((String) -> Unit)? = null,
) : AutoCloseable {
    private var controls by mutableStateOf(emptyList<Control>())
    var uiStyle by mutableStateOf(initialStyle)
        private set
    private var bottomSystemBarInsetDp by mutableStateOf(0.dp)
    private var textMetrics: TextMetrics? = null
    private var hostContext: Context? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val asyncRenderPending = AtomicBoolean(false)
    private var animationFrameScheduled = false
    private val animationFrameCallback = Choreographer.FrameCallback {
        animationFrameScheduled = false
        if (handle != 0L && textMetrics != null) {
            update(nativeTickAnimation(handle))
        }
    }

    init {
        requireMainThread()
        require(handle != 0L) { "Missing Swift renderer" }
    }

    fun setUIStyle(style: AndroidUIStyle) {
        requireMainThread()
        uiStyle = style
    }

    fun toggleUIStyle() {
        requireMainThread()
        uiStyle = if (uiStyle == AndroidUIStyle.IOS) AndroidUIStyle.ANDROID_NATIVE else AndroidUIStyle.IOS
    }

    /** Called from Swift (potentially off the UI thread) when async state/task/observable writes occur. */
    @Keep
    fun scheduleAsyncRender() {
        if (!asyncRenderPending.compareAndSet(false, true)) return
        mainHandler.post {
            asyncRenderPending.set(false)
            if (handle != 0L && textMetrics != null) {
                update(nativeFlushRender(handle))
            }
        }
    }

    /** Called from Swift's OpenURLAction environment hook. */
    @Keep
    fun openURL(url: String) {
        if (url.isEmpty()) return
        mainHandler.post {
            val custom = onOpenURL
            if (custom != null) {
                custom(url)
                return@post
            }
            val ctx = hostContext ?: return@post
            try {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                ctx.startActivity(intent)
            } catch (_: Throwable) {
            }
        }
    }

    private fun scheduleAnimationFrameIfNeeded(hasActiveAnimations: Boolean) {
        if (hasActiveAnimations && !animationFrameScheduled && handle != 0L) {
            animationFrameScheduled = true
            Choreographer.getInstance().postFrameCallback(animationFrameCallback)
        }
    }

    @Composable
    fun Content(modifier: Modifier = Modifier, bottomSystemBarInset: Dp = 0.dp) {
        bottomSystemBarInsetDp = bottomSystemBarInset
        hostContext = LocalContext.current
        var viewport by remember(this) { mutableStateOf(IntSize.Zero) }
        val measurer = rememberTextMeasurer()
        val density = LocalDensity.current
        val dark = isSystemInDarkTheme()
        val metrics = remember(measurer, density) { TextMetrics(measurer, density) }

        // Mount after Compose has measured the viewport, outside its measure/layout pass.
        LaunchedEffect(this, viewport, metrics) {
            if (handle != 0L && viewport.width > 0 && viewport.height > 0) {
                val invalidateMeasurements = textMetrics != metrics
                textMetrics = metrics
                nativeSetColorScheme(handle, dark)
                update(
                    nativeResize(
                        handle,
                        viewport.width / density.density.toDouble(),
                        viewport.height / density.density.toDouble(),
                        invalidateMeasurements,
                    )
                )
            }
        }

        // Keep SwiftUI's EnvironmentValues.colorScheme in sync with Android dark mode changes.
        LaunchedEffect(this, dark, metrics) {
            if (handle != 0L && textMetrics != null && viewport.width > 0 && viewport.height > 0) {
                update(nativeSetColorScheme(handle, dark))
            }
        }

        val snapshot = controls
        Box(modifier = modifier.fillMaxSize().clipToBounds().onSizeChanged { viewport = it }) {
            RenderNodeList(snapshot, metrics, Modifier.fillMaxSize())
        }
    }

    @Composable
    private fun RenderNodeList(
        nodes: List<Control>,
        metrics: TextMetrics,
        modifier: Modifier = Modifier,
    ) {
        val density = metrics.density
        Layout(
            modifier = modifier,
            content = {
                nodes.forEachIndexed { index, control ->
                    key("${control.kind}_${control.id}_$index") { RenderControl(control, metrics) }
                }
            },
        ) { children, constraints ->
            val scale = density.density
            val placeables = children.mapIndexed { index, child ->
                val frame = nodes[index]
                val width = (frame.width * scale).roundToInt().coerceAtLeast(0)
                val height = (frame.height * scale).roundToInt().coerceAtLeast(0)
                child.measure(Constraints.fitPrioritizingWidth(width, width, height, height))
            }
            val layoutW = if (constraints.hasBoundedWidth) constraints.maxWidth else constraints.minWidth
            val layoutH = if (constraints.hasBoundedHeight) constraints.maxHeight else constraints.minHeight
            layout(layoutW, layoutH) {
                placeables.forEachIndexed { index, child ->
                    val frame = nodes[index]
                    child.place((frame.x * scale).roundToInt(), (frame.y * scale).roundToInt())
                }
            }
        }
    }

    @Composable
    private fun RenderControl(control: Control, metrics: TextMetrics) {
        var baseModifier: Modifier = Modifier
        if (control.shadowColor != null && control.shadowRadius > 0.0) {
            val shape = RoundedCornerShape(control.cornerRadius.dp)
            baseModifier = baseModifier.shadow(
                elevation = control.shadowRadius.dp,
                shape = shape,
                ambientColor = control.shadowColor,
                spotColor = control.shadowColor,
            )
        }
        if (control.rotation != 0.0 || control.scaleX != 1.0 || control.scaleY != 1.0) {
            baseModifier = baseModifier.graphicsLayer(
                rotationZ = control.rotation.toFloat(),
                scaleX = control.scaleX.toFloat(),
                scaleY = control.scaleY.toFloat(),
            )
        }
        val clipCmds = control.clipCommands
        if (clipCmds != null && clipCmds.isNotEmpty()) {
            val scale = metrics.density.density
            val clipShape = remember(clipCmds, scale) {
                GenericShape { _, _ ->
                    addPath(buildComposePath(clipCmds, scale, 0f, 0f))
                }
            }
            baseModifier = baseModifier.clip(clipShape)
        }
        baseModifier = baseModifier.alpha(control.opacity).semantics {
            if (control.accessibilityLabel.isNotEmpty()) contentDescription = control.accessibilityLabel
            if (control.accessibilityHidden) hideFromAccessibility()
        }
        val style = control.font.style()
        val currentUIStyle = uiStyle

        when (control.kind) {
            "scroll" -> {
                val vScroll = rememberScrollState()
                val hScroll = rememberScrollState()
                val densityPx = metrics.density.density
                LaunchedEffect(control.scrollOffsetY) {
                    if (control.scrollVertical && control.scrollOffsetY > 0.0) {
                        val targetPx = (control.scrollOffsetY * densityPx).roundToInt()
                        if (kotlin.math.abs(vScroll.value - targetPx) > 2) {
                            vScroll.scrollTo(targetPx)
                        }
                    }
                }
                LaunchedEffect(control.scrollOffsetX) {
                    if (control.scrollHorizontal && control.scrollOffsetX > 0.0) {
                        val targetPx = (control.scrollOffsetX * densityPx).roundToInt()
                        if (kotlin.math.abs(hScroll.value - targetPx) > 2) {
                            hScroll.scrollTo(targetPx)
                        }
                    }
                }
                var scrollMod = baseModifier.fillMaxSize().clipToBounds()
                if (control.scrollVertical) {
                    scrollMod = scrollMod.verticalScroll(vScroll)
                }
                if (control.scrollHorizontal) {
                    scrollMod = scrollMod.horizontalScroll(hScroll)
                }
                val contentW = control.contentWidth.coerceAtLeast(control.width).dp
                val extraBottom = if (control.scrollVertical) bottomSystemBarInsetDp else 0.dp
                val contentH = control.contentHeight.coerceAtLeast(control.height).dp + extraBottom
                Box(modifier = scrollMod) {
                    RenderNodeList(
                        nodes = control.children,
                        metrics = metrics,
                        modifier = Modifier.width(contentW).height(contentH),
                    )
                }
            }

            "clip" -> {
                val clipMod = if (control.cornerRadius > 0.0) {
                    baseModifier.fillMaxSize().clip(RoundedCornerShape(control.cornerRadius.dp))
                } else {
                    baseModifier.fillMaxSize().clipToBounds()
                }
                Box(modifier = clipMod) {
                    RenderNodeList(
                        nodes = control.children,
                        metrics = metrics,
                        modifier = Modifier.fillMaxSize(),
                    )
                }
            }

            "shape" -> {
                var fill = control.background ?: control.color.takeIf { it != Color.Unspecified }
                val stroke = control.borderColor
                val borderW = control.borderWidth
                val radiusDp = control.cornerRadius

                // In Android Native (Material 3) mode, map iOS grouped canvas & 26pt grouped cards to native M3 OutlinedCard / theme background.
                if (currentUIStyle == AndroidUIStyle.ANDROID_NATIVE && fill != null) {
                    val isIosLightCanvas = fill == Color(0xFFF2F2F7)
                    val isIosGroupedCard = (fill == Color.White || fill == Color(0xFF1C1C1E)) && radiusDp >= 22.0
                    if (isIosGroupedCard) {
                        RenderMaterial3SectionCard(modifier = baseModifier)
                        return
                    }
                    if (isIosLightCanvas) {
                        fill = MaterialTheme.colorScheme.background
                    }
                }

                val strokePx = with(metrics.density) { borderW.dp.toPx() }
                val radiusPx = with(metrics.density) { radiusDp.dp.toPx() }
                Canvas(modifier = baseModifier.fillMaxSize()) {
                    val cr = CornerRadius(radiusPx, radiusPx)
                    if (fill != null && fill.alpha > 0f) {
                        drawRoundRect(color = fill, size = size, cornerRadius = cr, style = Fill)
                    }
                    if (stroke != null && stroke.alpha > 0f && strokePx > 0f) {
                        drawRoundRect(color = stroke, size = size, cornerRadius = cr, style = Stroke(width = strokePx))
                    }
                }
            }

            "divider" -> {
                RenderDualStyleDivider(uiStyle = currentUIStyle, modifier = baseModifier)
            }

            "checkbox" -> {
                RenderDualStyleCheckbox(
                    uiStyle = currentUIStyle,
                    checked = control.boolValue,
                    enabled = control.enabled,
                    tint = control.tint,
                    modifier = baseModifier,
                    onCheckedChange = { checked ->
                        if (handle != 0L) update(nativeBoolInput(handle, control.id, checked))
                    },
                )
            }

            "menu" -> {
                RenderDualStyleMenu(
                    uiStyle = currentUIStyle,
                    title = control.title ?: "",
                    items = control.items,
                    selectedIndex = control.intValue,
                    enabled = control.enabled,
                    tint = control.tint,
                    modifier = baseModifier,
                    onSelect = { idx ->
                        if (handle != 0L) update(nativeIntInput(handle, control.id, idx))
                    },
                )
            }

            "navStack" -> {
                val pageKey = control.subtitle ?: "0"
                val depth = control.intValue
                val pageBg = if (currentUIStyle == AndroidUIStyle.IOS) Color(0xFFF2F2F7) else MaterialTheme.colorScheme.background
                val navController = rememberNavController()
                val navBackStackEntry by navController.currentBackStackEntryAsState()
                val pageCache = remember { mutableStateMapOf<String, List<Control>>() }
                val depthStack = remember { mutableListOf("0") }
                pageCache[pageKey] = control.children

                // Sync native system Back / predictive back pops from NavHost back into SwiftUI NavigationStack.
                LaunchedEffect(navBackStackEntry) {
                    val entry = navBackStackEntry ?: return@LaunchedEffect
                    val navKey = if (entry.destination.route == "home") {
                        "0"
                    } else {
                        entry.arguments?.getString("key") ?: return@LaunchedEffect
                    }
                    if (navKey != pageKey) {
                        val idx = depthStack.lastIndexOf(navKey)
                        if (idx >= 0 && idx < depthStack.lastIndex) {
                            val poppedCount = depthStack.lastIndex - idx
                            repeat(poppedCount) { depthStack.removeAt(depthStack.lastIndex) }
                            repeat(poppedCount) {
                                if (handle != 0L) update(nativeBack(handle, control.id))
                            }
                        }
                    }
                }

                // Sync SwiftUI NavigationStack push / in-app Back button changes into NavHost.
                LaunchedEffect(pageKey, depth) {
                    val entry = navController.currentBackStackEntry
                    val currentKey = if (entry?.destination?.route == "home") {
                        "0"
                    } else {
                        entry?.arguments?.getString("key") ?: "0"
                    }
                    if (pageKey == currentKey && depth == depthStack.size - 1) return@LaunchedEffect

                    if (depth == 0 || pageKey == "0") {
                        if (depthStack.size > 1 || currentKey != "0") {
                            depthStack.clear()
                            depthStack.add("0")
                            if (!navController.popBackStack("home", inclusive = false)) {
                                while (navController.previousBackStackEntry != null) {
                                    navController.popBackStack()
                                }
                            }
                        }
                    } else if (depth > depthStack.size - 1) {
                        depthStack.add(pageKey)
                        navController.navigate("detail/$pageKey") {
                            launchSingleTop = true
                        }
                    } else if (depth < depthStack.size - 1) {
                        while (depthStack.size - 1 > depth && depthStack.size > 1) {
                            depthStack.removeAt(depthStack.lastIndex)
                            navController.popBackStack()
                        }
                    } else if (pageKey != currentKey) {
                        depthStack[depthStack.lastIndex] = pageKey
                        navController.navigate("detail/$pageKey") {
                            popUpTo("detail/$currentKey") { inclusive = true }
                            launchSingleTop = true
                        }
                    }
                }

                NavHost(
                    navController = navController,
                    startDestination = "home",
                    modifier = baseModifier.fillMaxSize().background(pageBg),
                ) {
                    composable("home") {
                        val nodes = pageCache["0"] ?: emptyList()
                        Box(modifier = Modifier.fillMaxSize().background(pageBg)) {
                            RenderNodeList(
                                nodes = nodes,
                                metrics = metrics,
                                modifier = Modifier.fillMaxSize(),
                            )
                        }
                    }
                    composable("detail/{key}") { backStackEntry ->
                        val key = backStackEntry.arguments?.getString("key") ?: "0"
                        val nodes = pageCache[key] ?: emptyList()
                        Box(modifier = Modifier.fillMaxSize().background(pageBg)) {
                            RenderNodeList(
                                nodes = nodes,
                                metrics = metrics,
                                modifier = Modifier.fillMaxSize(),
                            )
                        }
                    }
                }
            }

            "listItem" -> {
                val hitNode = control.children.lastOrNull { it.kind == "hitArea" }
                val nonHitChildren = if (hitNode != null) {
                    control.children.filter { it !== hitNode }
                } else {
                    control.children
                }
                val clickModifier = if (hitNode != null) {
                    baseModifier
                        .fillMaxSize()
                        .clickable(enabled = hitNode.enabled) {
                            if (handle != 0L) update(nativeTap(handle, hitNode.id))
                        }
                } else {
                    baseModifier.fillMaxSize()
                }

                if (currentUIStyle == AndroidUIStyle.ANDROID_NATIVE) {
                    val textNodes = nonHitChildren.filter { it.kind == "text" }
                    val headlineNode = if (textNodes.size == 1) textNodes.first() else null
                    val trailingNode = if (headlineNode != null) {
                        nonHitChildren.lastOrNull {
                            it.kind == "vector" && it.x > headlineNode.x
                        }
                    } else null

                    if (hitNode != null && headlineNode != null && trailingNode != null) {
                        val leadingNodes = nonHitChildren.filter {
                            it !== headlineNode && it !== trailingNode && it.x < headlineNode.x
                        }
                        ListItem(
                            headlineContent = {
                                Text(
                                    text = headlineNode.text,
                                    maxLines = 1,
                                    overflow = TextOverflow.Ellipsis,
                                )
                            },
                            leadingContent = if (leadingNodes.isNotEmpty()) {
                                {
                                    val minX = leadingNodes.minOf { it.x }
                                    val minY = leadingNodes.minOf { it.y }
                                    val maxX = leadingNodes.maxOf { it.x + it.width }
                                    val maxY = leadingNodes.maxOf { it.y + it.height }
                                    val shifted = leadingNodes.map { it.copy(x = it.x - minX, y = it.y - minY) }
                                    RenderNodeList(
                                        nodes = shifted,
                                        metrics = metrics,
                                        modifier = Modifier.width((maxX - minX).dp).height((maxY - minY).dp),
                                    )
                                }
                            } else null,
                            trailingContent = {
                                val shifted = listOf(trailingNode.copy(x = 0.0, y = 0.0))
                                RenderNodeList(
                                    nodes = shifted,
                                    metrics = metrics,
                                    modifier = Modifier.width(trailingNode.width.dp).height(trailingNode.height.dp),
                                )
                            },
                            modifier = clickModifier,
                            colors = ListItemDefaults.colors(
                                containerColor = Color.Transparent,
                            ),
                        )
                    } else {
                        val rowW = control.width.dp
                        val rowH = control.height.dp
                        ListItem(
                            headlineContent = {
                                Box(
                                    modifier = Modifier
                                        .requiredWidth(rowW)
                                        .requiredHeight(rowH)
                                ) {
                                    RenderNodeList(
                                        nodes = nonHitChildren,
                                        metrics = metrics,
                                        modifier = Modifier.fillMaxSize(),
                                    )
                                }
                            },
                            modifier = clickModifier,
                            colors = ListItemDefaults.colors(
                                containerColor = Color.Transparent,
                            ),
                        )
                    }
                } else {
                    Box(modifier = clickModifier) {
                        RenderNodeList(
                            nodes = nonHitChildren,
                            metrics = metrics,
                            modifier = Modifier.fillMaxSize(),
                        )
                    }
                }
            }

            "sheet" -> {
                val sheetW = control.contentWidth.coerceAtLeast(280.0).dp
                val sheetH = control.contentHeight.coerceAtLeast(220.0).dp
                RenderDualStyleSheet(
                    uiStyle = currentUIStyle,
                    onDismiss = {
                        if (handle != 0L) update(nativeDismissPresentation(handle))
                    },
                ) {
                    RenderNodeList(
                        nodes = control.children,
                        metrics = metrics,
                        modifier = Modifier.width(sheetW).height(sheetH),
                    )
                }
            }

            "gradient" -> {
                val colors = control.gradientColors
                val stops = control.gradientStops
                val radiusPx = with(metrics.density) { control.cornerRadius.dp.toPx() }
                Canvas(modifier = baseModifier.fillMaxSize()) {
                    if (colors.size >= 2) {
                        val colorStops = if (stops.size == colors.size) {
                            Array(colors.size) { i -> stops[i].toFloat() to colors[i] }
                        } else null
                        val brush = when (control.gradientKind) {
                            "radial" -> {
                                val center = Offset(
                                    control.gradientStartX.toFloat() * size.width,
                                    control.gradientStartY.toFloat() * size.height,
                                )
                                val radius = max(
                                    1f,
                                    if (control.gradientEndX > 0.0) {
                                        with(metrics.density) { control.gradientEndX.dp.toPx() }
                                    } else {
                                        max(size.width, size.height) * 0.5f
                                    },
                                )
                                if (colorStops != null) {
                                    Brush.radialGradient(colorStops = colorStops, center = center, radius = radius)
                                } else {
                                    Brush.radialGradient(colors = colors, center = center, radius = radius)
                                }
                            }
                            "angular" -> {
                                val center = Offset(
                                    control.gradientStartX.toFloat() * size.width,
                                    control.gradientStartY.toFloat() * size.height,
                                )
                                if (colorStops != null) {
                                    Brush.sweepGradient(colorStops = colorStops, center = center)
                                } else {
                                    Brush.sweepGradient(colors = colors, center = center)
                                }
                            }
                            else -> {
                                val start = Offset(
                                    control.gradientStartX.toFloat() * size.width,
                                    control.gradientStartY.toFloat() * size.height,
                                )
                                val end = Offset(
                                    control.gradientEndX.toFloat() * size.width,
                                    control.gradientEndY.toFloat() * size.height,
                                )
                                if (colorStops != null) {
                                    Brush.linearGradient(colorStops = colorStops, start = start, end = end)
                                } else {
                                    Brush.linearGradient(colors = colors, start = start, end = end)
                                }
                            }
                        }
                        val cr = CornerRadius(radiusPx, radiusPx)
                        drawRoundRect(brush = brush, size = size, cornerRadius = cr, style = Fill)
                    }
                }
            }

            "vector" -> {
                val bounds = control.vectorBounds
                val layers = control.vectorLayers
                if (bounds != null && bounds.size == 4 && !layers.isNullOrEmpty()) {
                    Canvas(modifier = baseModifier.fillMaxSize()) {
                        val vbX = bounds[0].toFloat()
                        val vbY = bounds[1].toFloat()
                        val vbW = bounds[2].toFloat().coerceAtLeast(0.001f)
                        val vbH = bounds[3].toFloat().coerceAtLeast(0.001f)
                        val scale = min(size.width / vbW, size.height / vbH)
                        val tx = (size.width - vbW * scale) / 2f - vbX * scale
                        val ty = (size.height - vbH * scale) / 2f - vbY * scale

                        for (layer in layers) {
                            val path = buildComposePath(layer.commands, scale, tx, ty)
                            if (layer.fill != null && layer.fill.alpha > 0f) {
                                drawPath(path = path, color = layer.fill, style = Fill)
                            }
                            if (layer.stroke != null && layer.stroke.alpha > 0f) {
                                val sw = (layer.strokeWidth.toFloat().coerceAtLeast(1f) * scale)
                                drawPath(
                                    path = path,
                                    color = layer.stroke,
                                    style = Stroke(width = sw, cap = StrokeCap.Round, join = StrokeJoin.Round),
                                )
                            }
                        }
                    }
                } else {
                    Box(modifier = baseModifier.fillMaxSize())
                }
            }

            "image" -> {
                val path = control.imagePath
                val bitmap = remember(path) {
                    if (path != null && !path.startsWith("sf://")) {
                        BitmapFactory.decodeFile(path)?.asImageBitmap()
                    } else {
                        null
                    }
                }
                if (bitmap != null) {
                    Image(
                        bitmap = bitmap,
                        contentDescription = control.accessibilityLabel.ifEmpty { null },
                        modifier = baseModifier.fillMaxSize(),
                        contentScale = ContentScale.Fit,
                    )
                } else {
                    Box(modifier = baseModifier.fillMaxSize())
                }
            }

            "hitArea" -> {
                Box(
                    modifier = baseModifier
                        .fillMaxSize()
                        .clickable(enabled = control.enabled) {
                            if (handle != 0L) update(nativeTap(handle, control.id))
                        },
                )
            }

            "dragArea" -> {
                val densityScale = metrics.density.density.toDouble()
                Box(
                    modifier = baseModifier
                        .fillMaxSize()
                        .pointerInput(control.id, control.enabled) {
                            if (!control.enabled) return@pointerInput
                            detectDragGestures(
                                onDragStart = { offset ->
                                    if (handle != 0L) {
                                        update(nativeDrag(handle, control.id, 2, control.x + offset.x / densityScale, control.y + offset.y / densityScale))
                                    }
                                },
                                onDrag = { change, _ ->
                                    change.consume()
                                    if (handle != 0L) {
                                        val pos = change.position
                                        update(nativeDrag(handle, control.id, 1, control.x + pos.x / densityScale, control.y + pos.y / densityScale))
                                    }
                                },
                                onDragEnd = {
                                    if (handle != 0L) {
                                        update(nativeDrag(handle, control.id, 3, control.x, control.y))
                                    }
                                },
                                onDragCancel = {
                                    if (handle != 0L) {
                                        update(nativeDrag(handle, control.id, 3, control.x, control.y))
                                    }
                                },
                            )
                        },
                )
            }

            "switch" -> {
                RenderDualStyleSwitch(
                    uiStyle = currentUIStyle,
                    checked = control.boolValue,
                    enabled = control.enabled,
                    tint = control.tint,
                    modifier = baseModifier,
                    onCheckedChange = { checked ->
                        if (handle != 0L) update(nativeBoolInput(handle, control.id, checked))
                    },
                )
            }

            "slider" -> {
                RenderDualStyleSlider(
                    uiStyle = currentUIStyle,
                    value = control.doubleValue,
                    minValue = control.minValue,
                    maxValue = control.maxValue,
                    stepValue = control.stepValue,
                    enabled = control.enabled,
                    tint = control.tint,
                    modifier = baseModifier,
                    onValueChange = { value, ended ->
                        if (handle != 0L) update(nativeDoubleInput(handle, control.id, value, ended))
                    },
                )
            }

            "segmented" -> {
                RenderDualStyleSegmentedControl(
                    uiStyle = currentUIStyle,
                    items = control.items,
                    selectedIndex = control.intValue,
                    enabled = control.enabled,
                    modifier = baseModifier,
                    onSelect = { idx ->
                        if (handle != 0L) update(nativeIntInput(handle, control.id, idx))
                    },
                )
            }

            "stepper" -> {
                RenderDualStyleStepper(
                    uiStyle = currentUIStyle,
                    enabled = control.enabled,
                    modifier = baseModifier,
                    onStep = { delta ->
                        if (handle != 0L) update(nativeStepInput(handle, control.id, delta))
                    },
                )
            }

            "progressLinear" -> {
                RenderDualStyleLinearProgress(
                    uiStyle = currentUIStyle,
                    progress = control.doubleValue,
                    tint = control.tint,
                    modifier = baseModifier,
                )
            }

            "progressCircular" -> {
                RenderDualStyleCircularProgress(
                    uiStyle = currentUIStyle,
                    tint = control.tint,
                    modifier = baseModifier,
                )
            }

            "navBar" -> {
                RenderDualStyleNavigationBar(
                    uiStyle = currentUIStyle,
                    title = control.title ?: "",
                    backTitle = control.subtitle ?: "Back",
                    canGoBack = control.canGoBack,
                    modifier = baseModifier,
                    onBack = {
                        if (handle != 0L) update(nativeBack(handle, control.id))
                    },
                    onToggleStyle = if (showStyleSwitcher) { { toggleUIStyle() } } else null,
                )
            }

            "tabBar" -> {
                RenderDualStyleTabBar(
                    uiStyle = currentUIStyle,
                    items = control.items,
                    itemIcons = control.itemIcons,
                    selectedIndex = control.intValue,
                    modifier = baseModifier.offset(y = -bottomSystemBarInsetDp),
                    onSelect = { idx ->
                        if (handle != 0L) update(nativeIntInput(handle, control.id, idx))
                    },
                )
            }

            "alert" -> {
                RenderDualStyleAlert(
                    uiStyle = currentUIStyle,
                    title = control.title ?: "",
                    message = control.subtitle ?: "",
                    actions = control.alertActions,
                    onAction = { idx ->
                        if (handle != 0L) update(nativeIntInput(handle, control.id, idx))
                    },
                    onDismiss = {
                        if (handle != 0L) update(nativeDismissPresentation(handle))
                    },
                )
            }

            "textField" -> {
                RenderDualStyleTextField(
                    uiStyle = currentUIStyle,
                    text = control.text,
                    placeholder = control.placeholder,
                    secure = control.secure,
                    multiline = control.multiline,
                    enabled = control.enabled,
                    textColor = control.color,
                    textStyle = style,
                    modifier = baseModifier,
                    onValueChange = { newText ->
                        if (handle != 0L) update(nativeTextInput(handle, control.id, newText))
                    },
                    onSubmit = {
                        if (handle != 0L) update(nativeSubmit(handle, control.id))
                    },
                )
            }

            "semanticButton", "button" -> {
                RenderDualStyleButton(
                    uiStyle = currentUIStyle,
                    title = control.title ?: control.text,
                    styleName = control.styleName ?: "borderedProminent",
                    role = control.subtitle ?: "",
                    tint = control.tint,
                    textColorOverride = control.color,
                    textStyle = style,
                    enabled = control.enabled,
                    modifier = baseModifier,
                    onClick = {
                        if (handle != 0L) update(nativeTap(handle, control.id))
                    },
                )
            }

            else -> {
                val lineHeight = if (control.lineSpacing == 0.0) style.lineHeight else with(metrics.density) {
                    val naturalHeight = metrics.measurer.measure("M", style, softWrap = false).size.height.toDp()
                    (naturalHeight + control.lineSpacing.dp).coerceAtLeast(0.dp).toSp()
                }
                val isSingleLine = control.lineLimit == 1
                Text(
                    text = control.text,
                    modifier = baseModifier,
                    color = control.color,
                    style = style,
                    textAlign = control.alignment,
                    lineHeight = lineHeight,
                    softWrap = !isSingleLine,
                    maxLines = control.lineLimit ?: Int.MAX_VALUE,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }

    private fun buildComposePath(commands: DoubleArray, scale: Float, tx: Float, ty: Float): Path {
        val path = Path()
        var i = 0
        while (i < commands.size) {
            when (commands[i].toInt()) {
                0 -> {
                    if (i + 2 < commands.size) {
                        path.moveTo(commands[i + 1].toFloat() * scale + tx, commands[i + 2].toFloat() * scale + ty)
                    }
                    i += 3
                }
                1 -> {
                    if (i + 2 < commands.size) {
                        path.lineTo(commands[i + 1].toFloat() * scale + tx, commands[i + 2].toFloat() * scale + ty)
                    }
                    i += 3
                }
                2 -> {
                    if (i + 6 < commands.size) {
                        path.cubicTo(
                            commands[i + 1].toFloat() * scale + tx, commands[i + 2].toFloat() * scale + ty,
                            commands[i + 3].toFloat() * scale + tx, commands[i + 4].toFloat() * scale + ty,
                            commands[i + 5].toFloat() * scale + tx, commands[i + 6].toFloat() * scale + ty,
                        )
                    }
                    i += 7
                }
                3 -> {
                    path.close()
                    i += 1
                }
                else -> i += 1
            }
        }
        return path
    }

    private fun update(snapshot: String?) {
        if (snapshot.isNullOrEmpty()) return
        val trimmed = snapshot.trimStart()
        if (trimmed.startsWith("{")) {
            val env = JSONObject(trimmed)
            if (env.has("uiStyle") && !env.isNull("uiStyle")) {
                when (env.getString("uiStyle").lowercase()) {
                    "ios" -> uiStyle = AndroidUIStyle.IOS
                    "android", "material", "material3", "native" -> uiStyle = AndroidUIStyle.ANDROID_NATIVE
                }
            }
            val nodes = env.optJSONArray("nodes") ?: JSONArray()
            controls = List(nodes.length()) { Control(nodes.getJSONObject(it)) }
            scheduleAnimationFrameIfNeeded(env.optBoolean("hasActiveAnimations", false))
        } else {
            val nodes = JSONArray(trimmed)
            controls = List(nodes.length()) { Control(nodes.getJSONObject(it)) }
        }
    }

    // Swift calls this during nativeResize/nativeTap. Coordinates return in logical points.
    private fun measureText(text: String, size: Double, family: String, weight: Int): Long {
        val metrics = checkNotNull(textMetrics)
        val style = ControlFont(size, family, weight).style()
        val measured = metrics.measurer.measure(text, style, softWrap = false).size
        val width = measured.width / metrics.density.density
        val height = measured.height / metrics.density.density
        return width.toRawBits().toLong().shl(32) or (height.toRawBits().toLong() and 0xffffffffL)
    }

    override fun close() {
        requireMainThread()
        val oldHandle = handle
        if (oldHandle == 0L) return
        handle = 0
        if (animationFrameScheduled) {
            animationFrameScheduled = false
            Choreographer.getInstance().removeFrameCallback(animationFrameCallback)
        }
        mainHandler.removeCallbacksAndMessages(null)
        asyncRenderPending.set(false)
        hostContext = null
        textMetrics = null
        nativeDestroy(oldHandle)
        controls = emptyList()
    }

    private fun requireMainThread() {
        check(Looper.myLooper() == Looper.getMainLooper()) { "SwiftUIComposeHost requires the UI thread" }
    }

    private data class TextMetrics(val measurer: TextMeasurer, val density: Density)

    private data class ControlFont(val size: Double, val family: String, val weight: Int) {
        fun style(): TextStyle {
            val fontWeight = weight.coerceIn(1, 1000)
            val fontFamily = when (family) {
                "Segoe UI", "sans-serif" -> FontFamily.SansSerif
                "Consolas", "monospace" -> FontFamily.Monospace
                "Georgia", "serif" -> FontFamily.Serif
                else -> {
                    val face = if (Build.VERSION.SDK_INT >= 28) {
                        Typeface.create(Typeface.create(family, Typeface.NORMAL), fontWeight, false)
                    } else {
                        Typeface.create(family, if (fontWeight >= 600) Typeface.BOLD else Typeface.NORMAL)
                    }
                    FontFamily(face)
                }
            }
            return TextStyle(fontSize = size.sp, fontFamily = fontFamily, fontWeight = FontWeight(fontWeight))
        }
    }

    private data class VectorLayerData(
        val commands: DoubleArray,
        val fill: Color?,
        val stroke: Color?,
        val strokeWidth: Double,
    )

    private data class Control(
        val id: Long,
        val kind: String,
        val button: Boolean,
        val text: String,
        val placeholder: String?,
        val secure: Boolean,
        val multiline: Boolean,
        val imagePath: String?,
        val vectorBounds: DoubleArray?,
        val vectorLayers: List<VectorLayerData>?,
        val x: Double,
        val y: Double,
        val width: Double,
        val height: Double,
        val font: ControlFont,
        val alignment: TextAlign,
        val lineSpacing: Double,
        val lineLimit: Int?,
        val enabled: Boolean,
        val opacity: Float,
        val rotation: Double,
        val scaleX: Double,
        val scaleY: Double,
        val clipCommands: DoubleArray?,
        val shadowColor: Color?,
        val shadowRadius: Double,
        val shadowX: Double,
        val shadowY: Double,
        val color: Color,
        val background: Color?,
        val borderColor: Color?,
        val borderWidth: Double,
        val cornerRadius: Double,
        val accessibilityLabel: String,
        val accessibilityHidden: Boolean,
        val scrollVertical: Boolean,
        val scrollHorizontal: Boolean,
        val scrollOffsetX: Double,
        val scrollOffsetY: Double,
        val contentWidth: Double,
        val contentHeight: Double,
        val children: List<Control>,
        val gradientKind: String?,
        val gradientColors: List<Color>,
        val gradientStops: List<Double>,
        val gradientStartX: Double,
        val gradientStartY: Double,
        val gradientEndX: Double,
        val gradientEndY: Double,
        val boolValue: Boolean,
        val doubleValue: Double,
        val minValue: Double,
        val maxValue: Double,
        val stepValue: Double,
        val intValue: Int,
        val items: List<String>,
        val itemIcons: List<String>,
        val title: String?,
        val subtitle: String?,
        val styleName: String?,
        val tint: Color?,
        val canGoBack: Boolean,
        val isIndeterminate: Boolean,
        val alertActions: List<AlertActionItem>,
    ) {
        constructor(node: JSONObject) : this(
            id = node.getLong("id"),
            kind = if (node.has("kind")) node.getString("kind") else if (node.getBoolean("button")) "button" else "text",
            button = node.optBoolean("button", false),
            text = node.optString("text", ""),
            placeholder = if (node.has("placeholder") && !node.isNull("placeholder")) node.getString("placeholder") else null,
            secure = node.optBoolean("secure", false),
            multiline = node.optBoolean("multiline", false),
            imagePath = if (node.has("imagePath") && !node.isNull("imagePath")) node.getString("imagePath") else null,
            vectorBounds = node.optJSONArray("vectorBounds")?.let { arr ->
                DoubleArray(arr.length()) { arr.getDouble(it) }
            },
            vectorLayers = node.optJSONArray("vectorLayers")?.let { arr ->
                List(arr.length()) { idx ->
                    val obj = arr.getJSONObject(idx)
                    val cmdsArr = obj.getJSONArray("commands")
                    VectorLayerData(
                        commands = DoubleArray(cmdsArr.length()) { cmdsArr.getDouble(it) },
                        fill = if (obj.has("fill") && !obj.isNull("fill")) Color(obj.getLong("fill").toInt()) else null,
                        stroke = if (obj.has("stroke") && !obj.isNull("stroke")) Color(obj.getLong("stroke").toInt()) else null,
                        strokeWidth = obj.optDouble("strokeWidth", 0.0),
                    )
                }
            },
            x = node.getDouble("x"),
            y = node.getDouble("y"),
            width = node.getDouble("width"),
            height = node.getDouble("height"),
            font = ControlFont(node.getDouble("fontSize"), node.getString("fontFamily"), node.getInt("fontWeight")),
            alignment = when (node.optString("alignment", "leading")) {
                "center" -> TextAlign.Center
                "trailing" -> TextAlign.End
                else -> TextAlign.Start
            },
            lineSpacing = node.optDouble("lineSpacing", 0.0),
            lineLimit = if (node.has("lineLimit") && !node.isNull("lineLimit")) node.getInt("lineLimit") else null,
            enabled = node.optBoolean("enabled", true),
            opacity = node.optDouble("opacity", 1.0).toFloat().coerceIn(0f, 1f),
            rotation = node.optDouble("rotation", 0.0),
            scaleX = node.optDouble("scaleX", 1.0),
            scaleY = node.optDouble("scaleY", 1.0),
            clipCommands = node.optJSONArray("clipCommands")?.let { arr ->
                DoubleArray(arr.length()) { arr.getDouble(it) }
            },
            shadowColor = if (node.has("shadowColor") && !node.isNull("shadowColor")) Color(node.getLong("shadowColor").toInt()) else null,
            shadowRadius = node.optDouble("shadowRadius", 0.0),
            shadowX = node.optDouble("shadowX", 0.0),
            shadowY = node.optDouble("shadowY", 0.0),
            color = if (node.has("foreground") && !node.isNull("foreground")) Color(node.getLong("foreground").toInt()) else Color.Unspecified,
            background = if (node.has("background") && !node.isNull("background")) Color(node.getLong("background").toInt()) else null,
            borderColor = if (node.has("borderColor") && !node.isNull("borderColor")) Color(node.getLong("borderColor").toInt()) else null,
            borderWidth = node.optDouble("borderWidth", 0.0),
            cornerRadius = node.optDouble("cornerRadius", 0.0),
            accessibilityLabel = node.optString("accessibilityLabel", ""),
            accessibilityHidden = node.optBoolean("accessibilityHidden", false),
            scrollVertical = node.optBoolean("scrollVertical", false),
            scrollHorizontal = node.optBoolean("scrollHorizontal", false),
            scrollOffsetX = node.optDouble("scrollOffsetX", 0.0),
            scrollOffsetY = node.optDouble("scrollOffsetY", 0.0),
            contentWidth = node.optDouble("contentWidth", 0.0),
            contentHeight = node.optDouble("contentHeight", 0.0),
            children = node.optJSONArray("children")?.let { arr ->
                List(arr.length()) { Control(arr.getJSONObject(it)) }
            } ?: emptyList(),
            gradientKind = if (node.has("gradientKind") && !node.isNull("gradientKind")) node.getString("gradientKind") else null,
            gradientColors = node.optJSONArray("gradientColors")?.let { arr ->
                List(arr.length()) { Color(arr.getLong(it).toInt()) }
            } ?: emptyList(),
            gradientStops = node.optJSONArray("gradientStops")?.let { arr ->
                List(arr.length()) { arr.getDouble(it) }
            } ?: emptyList(),
            gradientStartX = node.optDouble("gradientStartX", 0.0),
            gradientStartY = node.optDouble("gradientStartY", 0.0),
            gradientEndX = node.optDouble("gradientEndX", 0.0),
            gradientEndY = node.optDouble("gradientEndY", 1.0),
            boolValue = node.optBoolean("boolValue", false),
            doubleValue = node.optDouble("doubleValue", 0.0),
            minValue = node.optDouble("minValue", 0.0),
            maxValue = node.optDouble("maxValue", 1.0),
            stepValue = node.optDouble("stepValue", 0.0),
            intValue = node.optInt("intValue", 0),
            items = node.optJSONArray("items")?.let { arr ->
                List(arr.length()) { arr.getString(it) }
            } ?: emptyList(),
            itemIcons = node.optJSONArray("itemIcons")?.let { arr ->
                List(arr.length()) { arr.getString(it) }
            } ?: emptyList(),
            title = if (node.has("title") && !node.isNull("title")) node.getString("title") else null,
            subtitle = if (node.has("subtitle") && !node.isNull("subtitle")) node.getString("subtitle") else null,
            styleName = if (node.has("styleName") && !node.isNull("styleName")) node.getString("styleName") else null,
            tint = if (node.has("tint") && !node.isNull("tint")) Color(node.getLong("tint").toInt()) else null,
            canGoBack = node.optBoolean("canGoBack", false),
            isIndeterminate = node.optBoolean("isIndeterminate", false),
            alertActions = node.optJSONArray("alertActions")?.let { arr ->
                List(arr.length()) { idx ->
                    val obj = arr.getJSONObject(idx)
                    AlertActionItem(
                        title = obj.getString("title"),
                        role = obj.optString("role", "default"),
                        enabled = obj.optBoolean("enabled", true),
                    )
                }
            } ?: emptyList(),
        )
    }

    private external fun nativeResize(
        handle: Long, width: Double, height: Double, invalidateMeasurements: Boolean,
    ): String?
    private external fun nativeTap(handle: Long, id: Long): String?
    private external fun nativeTextInput(handle: Long, id: Long, text: String): String?
    private external fun nativeBoolInput(handle: Long, id: Long, value: Boolean): String?
    private external fun nativeDoubleInput(handle: Long, id: Long, value: Double, ended: Boolean): String?
    private external fun nativeIntInput(handle: Long, id: Long, value: Int): String?
    private external fun nativeStepInput(handle: Long, id: Long, delta: Int): String?
    private external fun nativeBack(handle: Long, id: Long): String?
    private external fun nativeDrag(handle: Long, id: Long, phase: Int, x: Double, y: Double): String?
    private external fun nativeDismissPresentation(handle: Long): String?
    private external fun nativeFlushRender(handle: Long): String?
    private external fun nativeTickAnimation(handle: Long): String?
    private external fun nativeSetColorScheme(handle: Long, isDark: Boolean): String?
    private external fun nativeSubmit(handle: Long, id: Long): String?
    private external fun nativeDestroy(handle: Long)
}
