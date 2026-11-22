package dev.crossswiftui.android

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

/** Visual presentation style for the Android compatibility layer. */
enum class AndroidUIStyle {
    /** Native Android Jetpack Compose Material 3 controls and aesthetics. */
    ANDROID_NATIVE,
    /** Authentic iOS 27 / UIKit Liquid Glass controls and aesthetics. */
    IOS,
}

data class AlertActionItem(
    val title: String,
    val role: String,
    val enabled: Boolean,
)

private object Ios27Palette {
    val SystemBlue = Color(0xFF007AFF)
    val SystemGreen = Color(0xFF34C759)
    val SystemRed = Color(0xFFFF3B30)
    val DisabledGray = Color(0xFF8E8E93)
    val FillTertiaryLight = Color(0x1F767680)
    val FillTertiaryDark = Color(0x3D767680)
    val TrackOffLight = Color(0x33787880)
    val TrackOffDark = Color(0x5C787880)
    val GlassSurfaceLight = Color(0xE8FFFFFF)
    val GlassSurfaceDark = Color(0xD82C2C2E)
    val AlertSurfaceLight = Color(0xF5F7F7FA)
    val AlertSurfaceDark = Color(0xF2242428)
    val AlertButtonLight = Color(0x14000000)
    val AlertButtonDark = Color(0x1FFFFFFF)

    fun specularRimBrush(dark: Boolean): Brush = Brush.verticalGradient(
        colors = if (dark) {
            listOf(Color.White.copy(alpha = 0.34f), Color.White.copy(alpha = 0.08f))
        } else {
            listOf(Color.White.copy(alpha = 0.92f), Color.White.copy(alpha = 0.24f))
        },
    )
}

private fun Modifier.ios27LiquidGlass(
    shape: Shape,
    dark: Boolean,
    elevation: Dp = 8.dp,
    fillOverride: Color? = null,
): Modifier {
    val fill = fillOverride ?: if (dark) Ios27Palette.GlassSurfaceDark else Ios27Palette.GlassSurfaceLight
    return this
        .shadow(
            elevation = elevation,
            shape = shape,
            ambientColor = Color.Black.copy(alpha = if (dark) 0.50f else 0.14f),
            spotColor = Color.Black.copy(alpha = if (dark) 0.55f else 0.16f),
        )
        .clip(shape)
        .background(fill)
        .border(width = 0.85.dp, brush = Ios27Palette.specularRimBrush(dark), shape = shape)
}

// MARK: - Switch / Toggle (iOS 27 Elongated Pill Thumb vs Material 3 Switch)

@Composable
internal fun RenderDualStyleSwitch(
    uiStyle: AndroidUIStyle,
    checked: Boolean,
    enabled: Boolean,
    tint: Color?,
    modifier: Modifier,
    onCheckedChange: (Boolean) -> Unit,
) {
    when (uiStyle) {
        AndroidUIStyle.ANDROID_NATIVE -> {
            val colors = if (tint != null) {
                SwitchDefaults.colors(
                    checkedTrackColor = tint,
                    checkedThumbColor = Color.White,
                )
            } else {
                SwitchDefaults.colors()
            }
            Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Switch(
                    checked = checked,
                    onCheckedChange = onCheckedChange,
                    enabled = enabled,
                    colors = colors,
                )
            }
        }

        AndroidUIStyle.IOS -> {
            val dark = isSystemInDarkTheme()
            val interactionSource = remember { MutableInteractionSource() }
            val pressed by interactionSource.collectIsPressedAsState()
            val activeColor = tint ?: Ios27Palette.SystemGreen
            val inactiveColor = if (dark) Ios27Palette.TrackOffDark else Ios27Palette.TrackOffLight
            val trackColor by animateColorAsState(
                targetValue = if (checked) activeColor else inactiveColor,
                label = "ios27SwitchTrack",
            )
            val thumbOffset by animateDpAsState(
                targetValue = if (checked) 24.dp else 2.dp,
                animationSpec = spring(dampingRatio = 0.76f, stiffness = 480f),
                label = "ios27SwitchThumb",
            )
            val thumbScaleX by animateFloatAsState(
                targetValue = if (pressed && enabled) 1.09f else 1f,
                animationSpec = spring(dampingRatio = 0.7f, stiffness = 520f),
                label = "ios27SwitchScaleX",
            )
            val thumbScaleY by animateFloatAsState(
                targetValue = if (pressed && enabled) 1.04f else 1f,
                animationSpec = spring(dampingRatio = 0.7f, stiffness = 520f),
                label = "ios27SwitchScaleY",
            )

            Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Box(
                    modifier = Modifier
                        .size(width = 62.dp, height = 28.dp)
                        .clip(CircleShape)
                        .background(trackColor.copy(alpha = if (enabled) trackColor.alpha else trackColor.alpha * 0.42f))
                        .clickable(
                            enabled = enabled,
                            interactionSource = interactionSource,
                            indication = null,
                        ) { onCheckedChange(!checked) },
                    contentAlignment = Alignment.CenterStart,
                ) {
                    // iOS 27 elongated capsule thumb (36x24dp)
                    Box(
                        modifier = Modifier
                            .offset(x = thumbOffset)
                            .size(width = 36.dp, height = 24.dp)
                            .graphicsLayer {
                                scaleX = thumbScaleX
                                scaleY = thumbScaleY
                            }
                            .shadow(
                                elevation = if (enabled) 3.dp else 0.dp,
                                shape = CircleShape,
                                ambientColor = Color.Black.copy(alpha = 0.16f),
                                spotColor = Color.Black.copy(alpha = 0.20f),
                            )
                            .clip(CircleShape)
                            .background(Color.White.copy(alpha = if (enabled) 1f else 0.88f))
                            .border(
                                width = 0.5.dp,
                                color = Color.Black.copy(alpha = 0.05f),
                                shape = CircleShape,
                            ),
                    )
                }
            }
        }
    }
}

// MARK: - Slider (iOS 27 Thick Track + Elongated Capsule Thumb vs Material 3 Slider)

@Composable
internal fun RenderDualStyleSlider(
    uiStyle: AndroidUIStyle,
    value: Double,
    minValue: Double,
    maxValue: Double,
    stepValue: Double,
    enabled: Boolean,
    tint: Color?,
    modifier: Modifier,
    onValueChange: (Double, Boolean) -> Unit,
) {
    val span = (maxValue - minValue).coerceAtLeast(1e-6)
    var localValue by remember(value) { mutableFloatStateOf(value.toFloat()) }
    var isDragging by remember { mutableStateOf(false) }
    val displayValue = if (isDragging) localValue else value.toFloat()

    when (uiStyle) {
        AndroidUIStyle.ANDROID_NATIVE -> {
            val steps = if (stepValue > 0.0) ((span / stepValue).roundToInt() - 1).coerceAtLeast(0) else 0
            val activeTint = tint ?: MaterialTheme.colorScheme.primary
            Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Slider(
                    value = displayValue.coerceIn(minValue.toFloat(), maxValue.toFloat()),
                    onValueChange = { v ->
                        isDragging = true
                        localValue = v
                        onValueChange(v.toDouble(), false)
                    },
                    onValueChangeFinished = {
                        isDragging = false
                        onValueChange(localValue.toDouble(), true)
                    },
                    valueRange = minValue.toFloat()..maxValue.toFloat(),
                    steps = steps,
                    enabled = enabled,
                    colors = SliderDefaults.colors(
                        thumbColor = activeTint,
                        activeTrackColor = activeTint,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }

        AndroidUIStyle.IOS -> {
            val dark = isSystemInDarkTheme()
            val activeColor = if (enabled) (tint ?: Ios27Palette.SystemBlue) else Ios27Palette.DisabledGray.copy(alpha = 0.45f)
            val inactiveColor = if (dark) Color(0x40FFFFFF) else Color(0x22787880)
            var trackWidthPx by remember { mutableFloatStateOf(1f) }
            val fraction = ((displayValue - minValue.toFloat()) / span.toFloat()).coerceIn(0f, 1f)
            val thumbExpand by animateFloatAsState(
                targetValue = if (isDragging && enabled) 1.09f else 1f,
                animationSpec = spring(dampingRatio = 0.72f, stiffness = 460f),
                label = "ios27SliderThumbScale",
            )

            fun valueAtX(x: Float): Double {
                val f = (x / trackWidthPx).coerceIn(0f, 1f)
                var raw = minValue + f * span
                if (stepValue > 0.0) {
                    raw = minValue + ((raw - minValue) / stepValue).roundToInt() * stepValue
                }
                return raw.coerceIn(minValue, maxValue)
            }

            Box(
                modifier = modifier
                    .fillMaxSize()
                    .onSizeChanged { trackWidthPx = it.width.toFloat().coerceAtLeast(1f) }
                    .pointerInput(enabled, minValue, maxValue, stepValue) {
                        if (!enabled) return@pointerInput
                        detectTapGestures { offset ->
                            val next = valueAtX(offset.x)
                            localValue = next.toFloat()
                            onValueChange(next, true)
                        }
                    }
                    .pointerInput(enabled, minValue, maxValue, stepValue) {
                        if (!enabled) return@pointerInput
                        detectHorizontalDragGestures(
                            onDragStart = { offset ->
                                isDragging = true
                                val next = valueAtX(offset.x)
                                localValue = next.toFloat()
                                onValueChange(next, false)
                            },
                            onHorizontalDrag = { change, _ ->
                                change.consume()
                                val next = valueAtX(change.position.x)
                                localValue = next.toFloat()
                                onValueChange(next, false)
                            },
                            onDragEnd = {
                                isDragging = false
                                onValueChange(localValue.toDouble(), true)
                            },
                            onDragCancel = {
                                isDragging = false
                                onValueChange(localValue.toDouble(), true)
                            },
                        )
                    },
                contentAlignment = Alignment.CenterStart,
            ) {
                Canvas(modifier = Modifier.fillMaxSize()) {
                    val thumbW = 36.dp.toPx() * thumbExpand
                    val thumbH = 22.dp.toPx() * thumbExpand
                    val halfThumbW = thumbW / 2f
                    val trackHeight = 6.dp.toPx()
                    val centerY = size.height / 2f
                    val startX = halfThumbW
                    val endX = (size.width - halfThumbW).coerceAtLeast(startX + 1f)
                    val usableW = endX - startX
                    val thumbCenterX = startX + usableW * fraction

                    // Inactive capsule track
                    drawRoundRect(
                        color = inactiveColor,
                        topLeft = Offset(startX - 4.dp.toPx(), centerY - trackHeight / 2f),
                        size = Size(usableW + 8.dp.toPx(), trackHeight),
                        cornerRadius = CornerRadius(trackHeight / 2f, trackHeight / 2f),
                    )
                    // Active capsule track
                    drawRoundRect(
                        color = activeColor,
                        topLeft = Offset(startX - 4.dp.toPx(), centerY - trackHeight / 2f),
                        size = Size((thumbCenterX - startX + 4.dp.toPx()).coerceAtLeast(0f), trackHeight),
                        cornerRadius = CornerRadius(trackHeight / 2f, trackHeight / 2f),
                    )

                    val thumbLeft = thumbCenterX - halfThumbW
                    val thumbTop = centerY - thumbH / 2f
                    val thumbCR = CornerRadius(thumbH / 2f, thumbH / 2f)

                    // Soft drop shadow
                    drawRoundRect(
                        color = Color.Black.copy(alpha = if (enabled) 0.18f else 0.08f),
                        topLeft = Offset(thumbLeft, thumbTop + 1.8.dp.toPx()),
                        size = Size(thumbW, thumbH),
                        cornerRadius = thumbCR,
                    )
                    // Elongated white Liquid Glass pill thumb
                    drawRoundRect(
                        color = if (enabled) Color.White else Color(0xFFF2F2F7),
                        topLeft = Offset(thumbLeft, thumbTop),
                        size = Size(thumbW, thumbH),
                        cornerRadius = thumbCR,
                    )
                    // Hairline specular rim
                    drawRoundRect(
                        color = Color.Black.copy(alpha = 0.06f),
                        topLeft = Offset(thumbLeft, thumbTop),
                        size = Size(thumbW, thumbH),
                        cornerRadius = thumbCR,
                        style = Stroke(width = 0.75.dp.toPx()),
                    )
                }
            }
        }
    }
}

// MARK: - Segmented Control (iOS 27 Full Capsule vs Material 3 SegmentedButtonRow)

@Composable
internal fun RenderDualStyleSegmentedControl(
    uiStyle: AndroidUIStyle,
    items: List<String>,
    selectedIndex: Int,
    enabled: Boolean,
    modifier: Modifier,
    onSelect: (Int) -> Unit,
) {
    if (items.isEmpty()) return
    when (uiStyle) {
        AndroidUIStyle.ANDROID_NATIVE -> {
            Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                    items.forEachIndexed { index, label ->
                        SegmentedButton(
                            selected = index == selectedIndex,
                            onClick = { if (enabled) onSelect(index) },
                            enabled = enabled,
                            shape = SegmentedButtonDefaults.itemShape(index = index, count = items.size),
                            icon = {},
                        ) {
                            Text(
                                text = label,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                                fontSize = 13.sp,
                            )
                        }
                    }
                }
            }
        }

        AndroidUIStyle.IOS -> {
            val dark = isSystemInDarkTheme()
            val trackBg = if (dark) Ios27Palette.FillTertiaryDark else Ios27Palette.FillTertiaryLight
            val thumbBg = if (dark) Color(0xFF636366) else Color.White
            val textColor = if (dark) Color.White else Color.Black
            val dividerColor = if (dark) Color(0x33FFFFFF) else Color(0x20000000)

            Row(
                modifier = modifier
                    .fillMaxSize()
                    .clip(CircleShape)
                    .background(trackBg)
                    .padding(3.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                items.forEachIndexed { index, label ->
                    val selected = index == selectedIndex
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .then(
                                if (selected) {
                                    Modifier
                                        .shadow(
                                            elevation = 3.dp,
                                            shape = CircleShape,
                                            ambientColor = Color.Black.copy(alpha = 0.12f),
                                            spotColor = Color.Black.copy(alpha = 0.16f),
                                        )
                                        .clip(CircleShape)
                                        .background(thumbBg)
                                        .border(0.6.dp, Ios27Palette.specularRimBrush(dark), CircleShape)
                                } else {
                                    Modifier.clip(CircleShape)
                                }
                            )
                            .clickable(enabled = enabled) { onSelect(index) },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = label,
                            color = textColor.copy(alpha = if (enabled) 1f else 0.4f),
                            fontSize = 14.sp,
                            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.padding(horizontal = 8.dp),
                        )
                    }
                    if (index < items.lastIndex && index != selectedIndex && index + 1 != selectedIndex) {
                        Box(
                            modifier = Modifier
                                .width(1.dp)
                                .height(16.dp)
                                .background(dividerColor),
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Stepper (iOS 27 Full Capsule vs Material 3 Tonal Pair)

@Composable
internal fun RenderDualStyleStepper(
    uiStyle: AndroidUIStyle,
    enabled: Boolean,
    modifier: Modifier,
    onStep: (Int) -> Unit,
) {
    when (uiStyle) {
        AndroidUIStyle.ANDROID_NATIVE -> {
            Row(
                modifier = modifier.fillMaxSize(),
                horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.End),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                FilledTonalIconButton(
                    onClick = { onStep(-1) },
                    enabled = enabled,
                    modifier = Modifier.size(width = 44.dp, height = 34.dp),
                ) {
                    Text("−", fontSize = 18.sp, fontWeight = FontWeight.Medium)
                }
                FilledTonalIconButton(
                    onClick = { onStep(1) },
                    enabled = enabled,
                    modifier = Modifier.size(width = 44.dp, height = 34.dp),
                ) {
                    Text("+", fontSize = 18.sp, fontWeight = FontWeight.Medium)
                }
            }
        }

        AndroidUIStyle.IOS -> {
            val dark = isSystemInDarkTheme()
            val bg = if (dark) Ios27Palette.FillTertiaryDark else Ios27Palette.FillTertiaryLight
            val fg = (if (dark) Color.White else Color.Black).copy(alpha = if (enabled) 1f else 0.35f)
            val div = if (dark) Color(0x33FFFFFF) else Color(0x22000000)

            Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.CenterEnd) {
                Row(
                    modifier = Modifier
                        .size(width = 96.dp, height = 34.dp)
                        .clip(CircleShape)
                        .background(bg)
                        .border(0.6.dp, Ios27Palette.specularRimBrush(dark), CircleShape),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .clickable(enabled = enabled) { onStep(-1) },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("−", color = fg, fontSize = 20.sp, fontWeight = FontWeight.Normal)
                    }
                    Box(modifier = Modifier.width(1.dp).height(18.dp).background(div))
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .clickable(enabled = enabled) { onStep(1) },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("+", color = fg, fontSize = 20.sp, fontWeight = FontWeight.Normal)
                    }
                }
            }
        }
    }
}

// MARK: - Semantic Button (iOS 27 Full Capsule + Press Flex vs Material 3 Buttons)

@Composable
internal fun RenderDualStyleButton(
    uiStyle: AndroidUIStyle,
    title: String,
    styleName: String,
    role: String,
    tint: Color?,
    textColorOverride: Color,
    textStyle: TextStyle,
    enabled: Boolean,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    val isDestructive = role == "destructive"
    when (uiStyle) {
        AndroidUIStyle.ANDROID_NATIVE -> {
            val accent = when {
                isDestructive -> MaterialTheme.colorScheme.error
                tint != null -> tint
                else -> MaterialTheme.colorScheme.primary
            }
            when (styleName) {
                "borderedProminent", "filled" -> {
                    Button(
                        onClick = onClick,
                        enabled = enabled,
                        modifier = modifier.fillMaxSize(),
                        colors = ButtonDefaults.buttonColors(containerColor = accent),
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp),
                    ) {
                        Text(title, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }

                "bordered", "gray", "tinted" -> {
                    FilledTonalButton(
                        onClick = onClick,
                        enabled = enabled,
                        modifier = modifier.fillMaxSize(),
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp),
                    ) {
                        Text(
                            title,
                            fontSize = 14.sp,
                            color = if (isDestructive) MaterialTheme.colorScheme.error else Color.Unspecified,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }

                "borderless", "link", "plain" -> {
                    TextButton(
                        onClick = onClick,
                        enabled = enabled,
                        modifier = modifier.fillMaxSize(),
                        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 0.dp),
                    ) {
                        Text(title, fontSize = 14.sp, color = accent, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }

                else -> {
                    OutlinedButton(
                        onClick = onClick,
                        enabled = enabled,
                        modifier = modifier.fillMaxSize(),
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp),
                    ) {
                        Text(title, fontSize = 14.sp, color = accent, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }

        AndroidUIStyle.IOS -> {
            val dark = isSystemInDarkTheme()
            val interactionSource = remember { MutableInteractionSource() }
            val pressed by interactionSource.collectIsPressedAsState()
            val pressScale by animateFloatAsState(
                targetValue = if (pressed && enabled) 0.96f else 1f,
                animationSpec = spring(dampingRatio = 0.72f, stiffness = 500f),
                label = "ios27ButtonPress",
            )
            val accent = when {
                isDestructive -> Ios27Palette.SystemRed
                tint != null -> tint
                else -> Ios27Palette.SystemBlue
            }
            val isBorderless = styleName == "borderless" || styleName == "link" || styleName == "plain"
            val isFilled = styleName == "borderedProminent" || styleName == "filled"
            val isTinted = styleName == "tinted" || (styleName == "bordered" && tint != null && !isDestructive)

            val (bgColor, fgColor) = when {
                isFilled -> accent to Color.White
                isTinted -> accent.copy(alpha = 0.16f) to accent
                isBorderless -> Color.Transparent to (
                    if (textColorOverride != Color.Unspecified && !isDestructive) textColorOverride else accent
                )
                else -> (if (dark) Ios27Palette.FillTertiaryDark else Ios27Palette.FillTertiaryLight) to accent
            }
            val effectiveBg = bgColor.copy(alpha = if (enabled) bgColor.alpha else bgColor.alpha * 0.45f)
            val effectiveFg = fgColor.copy(alpha = if (enabled) 1f else 0.42f)

            Box(
                modifier = modifier
                    .fillMaxSize()
                    .graphicsLayer {
                        scaleX = pressScale
                        scaleY = pressScale
                    }
                    .clip(CircleShape)
                    .background(effectiveBg)
                    .then(
                        if (!isBorderless && enabled) {
                            Modifier.border(
                                width = 0.6.dp,
                                brush = Brush.verticalGradient(
                                    listOf(
                                        Color.White.copy(alpha = if (isFilled) 0.35f else 0.65f),
                                        Color.White.copy(alpha = 0.05f),
                                    )
                                ),
                                shape = CircleShape,
                            )
                        } else Modifier
                    )
                    .clickable(
                        enabled = enabled,
                        interactionSource = interactionSource,
                        indication = null,
                        onClick = onClick,
                    )
                    .padding(horizontal = 4.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = title,
                    color = effectiveFg,
                    fontSize = 14.sp,
                    fontWeight = if (isFilled || isTinted) FontWeight.SemiBold else FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

// MARK: - TextField

@Composable
internal fun RenderDualStyleTextField(
    uiStyle: AndroidUIStyle,
    text: String,
    placeholder: String?,
    secure: Boolean,
    multiline: Boolean = false,
    enabled: Boolean,
    textColor: Color,
    textStyle: TextStyle,
    modifier: Modifier,
    onValueChange: (String) -> Unit,
    onSubmit: (() -> Unit)? = null,
) {
    val visualTransformation = if (secure && !multiline) PasswordVisualTransformation() else VisualTransformation.None
    val keyboardOptions = if (multiline) KeyboardOptions.Default else KeyboardOptions(imeAction = ImeAction.Done)
    val keyboardActions = if (!multiline && onSubmit != null) {
        KeyboardActions(onDone = { onSubmit() })
    } else {
        KeyboardActions.Default
    }
    when (uiStyle) {
        AndroidUIStyle.ANDROID_NATIVE -> {
            OutlinedTextField(
                value = text,
                onValueChange = onValueChange,
                enabled = enabled,
                singleLine = !multiline,
                placeholder = if (!placeholder.isNullOrEmpty()) {
                    { Text(placeholder, maxLines = if (multiline) Int.MAX_VALUE else 1, overflow = TextOverflow.Ellipsis) }
                } else null,
                visualTransformation = visualTransformation,
                keyboardOptions = keyboardOptions,
                keyboardActions = keyboardActions,
                modifier = modifier.fillMaxSize(),
            )
        }

        AndroidUIStyle.IOS -> {
            val dark = isSystemInDarkTheme()
            val fillBg = if (dark) Color(0xFF2C2C2E) else Color(0x14767680)
            val resolvedTextColor = if (textColor != Color.Unspecified) textColor else if (dark) Color.White else Color.Black
            val placeholderColor = if (dark) Color(0x88EBEBF5) else Color(0x783C3C43)
            val shape = RoundedCornerShape(14.dp)

            Box(
                modifier = modifier
                    .fillMaxSize()
                    .clip(shape)
                    .background(fillBg)
                    .border(0.6.dp, Ios27Palette.specularRimBrush(dark), shape)
                    .padding(horizontal = 14.dp, vertical = if (multiline) 10.dp else 0.dp),
                contentAlignment = if (multiline) Alignment.TopStart else Alignment.CenterStart,
            ) {
                if (text.isEmpty() && !placeholder.isNullOrEmpty()) {
                    Text(
                        text = placeholder,
                        color = placeholderColor,
                        style = textStyle,
                        maxLines = if (multiline) Int.MAX_VALUE else 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                BasicTextField(
                    value = text,
                    onValueChange = onValueChange,
                    enabled = enabled,
                    singleLine = !multiline,
                    textStyle = textStyle.copy(color = resolvedTextColor),
                    cursorBrush = SolidColor(Ios27Palette.SystemBlue),
                    visualTransformation = visualTransformation,
                    keyboardOptions = keyboardOptions,
                    keyboardActions = keyboardActions,
                    modifier = if (multiline) Modifier.fillMaxSize() else Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

// MARK: - ProgressView & ActivityIndicator

@Composable
internal fun RenderDualStyleLinearProgress(
    uiStyle: AndroidUIStyle,
    progress: Double,
    tint: Color?,
    modifier: Modifier,
) {
    val clamped = progress.toFloat().coerceIn(0f, 1f)
    when (uiStyle) {
        AndroidUIStyle.ANDROID_NATIVE -> {
            val active = tint ?: MaterialTheme.colorScheme.primary
            Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                LinearProgressIndicator(
                    progress = { clamped },
                    color = active,
                    modifier = Modifier.fillMaxWidth().height(5.dp).clip(CircleShape),
                )
            }
        }

        AndroidUIStyle.IOS -> {
            val dark = isSystemInDarkTheme()
            val active = tint ?: Ios27Palette.SystemBlue
            val track = if (dark) Color(0x33FFFFFF) else Color(0x1F767680)
            Canvas(modifier = modifier.fillMaxSize()) {
                val h = 5.dp.toPx()
                val top = (size.height - h) / 2f
                val cr = CornerRadius(h / 2f, h / 2f)
                drawRoundRect(color = track, topLeft = Offset(0f, top), size = Size(size.width, h), cornerRadius = cr)
                if (clamped > 0f) {
                    drawRoundRect(
                        color = active,
                        topLeft = Offset(0f, top),
                        size = Size(size.width * clamped, h),
                        cornerRadius = cr,
                    )
                }
            }
        }
    }
}

@Composable
internal fun RenderDualStyleCircularProgress(
    uiStyle: AndroidUIStyle,
    tint: Color?,
    modifier: Modifier,
) {
    when (uiStyle) {
        AndroidUIStyle.ANDROID_NATIVE -> {
            val color = tint ?: MaterialTheme.colorScheme.primary
            Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(
                    color = color,
                    strokeWidth = 2.5.dp,
                    modifier = Modifier.size(22.dp),
                )
            }
        }

        AndroidUIStyle.IOS -> {
            val dark = isSystemInDarkTheme()
            val baseColor = tint ?: if (dark) Color(0xFFEBEBF5) else Color(0xFF3C3C43)
            val transition = rememberInfiniteTransition(label = "iosSpinner")
            val phase by transition.animateFloat(
                initialValue = 0f,
                targetValue = 12f,
                animationSpec = infiniteRepeatable(
                    animation = tween(durationMillis = 900, easing = LinearEasing),
                    repeatMode = RepeatMode.Restart,
                ),
                label = "iosSpinnerPhase",
            )
            val activeSpoke = phase.toInt() % 12
            Canvas(modifier = modifier.fillMaxSize()) {
                val radius = minOf(size.width, size.height) / 2f
                val inner = radius * 0.48f
                val outer = radius * 0.92f
                val strokeW = (radius * 0.17f).coerceAtLeast(1.8.dp.toPx())
                val cx = size.width / 2f
                val cy = size.height / 2f
                for (i in 0 until 12) {
                    val dist = (i - activeSpoke + 12) % 12
                    val alpha = 0.22f + 0.78f * (dist / 11f)
                    val angle = (i * 30.0 - 90.0) * PI / 180.0
                    val cosA = cos(angle).toFloat()
                    val sinA = sin(angle).toFloat()
                    drawLine(
                        color = baseColor.copy(alpha = alpha),
                        start = Offset(cx + cosA * inner, cy + sinA * inner),
                        end = Offset(cx + cosA * outer, cy + sinA * outer),
                        strokeWidth = strokeW,
                        cap = StrokeCap.Round,
                    )
                }
            }
        }
    }
}

// MARK: - Navigation Bar (iOS 27 Floating Circular Liquid Glass Back Button vs Material 3 TopAppBar)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun RenderDualStyleNavigationBar(
    uiStyle: AndroidUIStyle,
    title: String,
    backTitle: String,
    canGoBack: Boolean,
    modifier: Modifier,
    onBack: () -> Unit,
    onToggleStyle: (() -> Unit)? = null,
) {
    when (uiStyle) {
        AndroidUIStyle.ANDROID_NATIVE -> {
            TopAppBar(
                modifier = modifier.fillMaxSize(),
                windowInsets = WindowInsets(0, 0, 0, 0),
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
                title = {
                    Text(
                        text = title,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                navigationIcon = {
                    if (canGoBack) {
                        IconButton(onClick = onBack) {
                            DrawArrowBackIcon(color = MaterialTheme.colorScheme.onSurface)
                        }
                    }
                },
                actions = {
                    if (onToggleStyle != null) {
                        FilledTonalButton(
                            onClick = onToggleStyle,
                            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp),
                            modifier = Modifier.padding(end = 8.dp).height(32.dp),
                        ) {
                            Text(
                                text = "M3",
                                fontSize = 12.sp,
                                fontWeight = FontWeight.SemiBold,
                            )
                        }
                    }
                },
            )
        }

        AndroidUIStyle.IOS -> {
            val dark = isSystemInDarkTheme()
            val fg = if (dark) Color.White else Color.Black
            val interactionSource = remember { MutableInteractionSource() }
            val pressed by interactionSource.collectIsPressedAsState()
            val backScale by animateFloatAsState(
                targetValue = if (pressed) 0.92f else 1f,
                animationSpec = spring(dampingRatio = 0.7f, stiffness = 500f),
                label = "ios27BackScale",
            )

            Box(
                modifier = modifier
                    .fillMaxSize()
                    .background(Color.Transparent)
                    .padding(horizontal = 16.dp),
            ) {
                if (canGoBack) {
                    // iOS 27 floating circular Liquid Glass back button
                    Box(
                        modifier = Modifier
                            .align(Alignment.CenterStart)
                            .size(40.dp)
                            .graphicsLayer {
                                scaleX = backScale
                                scaleY = backScale
                            }
                            .ios27LiquidGlass(shape = CircleShape, dark = dark, elevation = 6.dp)
                            .clickable(
                                interactionSource = interactionSource,
                                indication = null,
                                onClick = onBack,
                            ),
                        contentAlignment = Alignment.Center,
                    ) {
                        DrawChevronBackIcon(color = fg)
                    }
                }

                Text(
                    text = title,
                    color = fg,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .align(Alignment.Center)
                        .padding(horizontal = if (canGoBack || onToggleStyle != null) 72.dp else 16.dp),
                )

                if (onToggleStyle != null) {
                    val pillInteraction = remember { MutableInteractionSource() }
                    val pillPressed by pillInteraction.collectIsPressedAsState()
                    val pillScale by animateFloatAsState(
                        targetValue = if (pillPressed) 0.94f else 1f,
                        animationSpec = spring(dampingRatio = 0.7f, stiffness = 500f),
                        label = "ios27StylePillScale",
                    )
                    Box(
                        modifier = Modifier
                            .align(Alignment.CenterEnd)
                            .height(34.dp)
                            .graphicsLayer {
                                scaleX = pillScale
                                scaleY = pillScale
                            }
                            .ios27LiquidGlass(shape = CircleShape, dark = dark, elevation = 6.dp)
                            .clickable(
                                interactionSource = pillInteraction,
                                indication = null,
                                onClick = onToggleStyle,
                            )
                            .padding(horizontal = 12.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = "iOS 27",
                            color = Ios27Palette.SystemBlue,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Tab Bar (iOS 27 Floating Liquid Glass Pill vs Material 3 NavigationBar)

@Composable
internal fun RenderDualStyleTabBar(
    uiStyle: AndroidUIStyle,
    items: List<String>,
    itemIcons: List<String>,
    selectedIndex: Int,
    modifier: Modifier,
    onSelect: (Int) -> Unit,
) {
    if (items.isEmpty()) return
    when (uiStyle) {
        AndroidUIStyle.ANDROID_NATIVE -> {
            NavigationBar(modifier = modifier.fillMaxSize()) {
                items.forEachIndexed { idx, label ->
                    val selected = idx == selectedIndex
                    val iconName = itemIcons.getOrNull(idx) ?: ""
                    NavigationBarItem(
                        selected = selected,
                        onClick = { onSelect(idx) },
                        icon = {
                            DrawTabGlyph(
                                name = iconName,
                                color = if (selected) {
                                    MaterialTheme.colorScheme.onSecondaryContainer
                                } else {
                                    MaterialTheme.colorScheme.onSurfaceVariant
                                },
                            )
                        },
                        label = { Text(label, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                    )
                }
            }
        }

        AndroidUIStyle.IOS -> {
            val dark = isSystemInDarkTheme()
            val pillBg = if (dark) Color(0x30FFFFFF) else Color(0x18007AFF)
            val inactiveFg = if (dark) Color(0xFF98989D) else Color(0xFF6E6E73)

            Box(
                modifier = modifier
                    .fillMaxSize()
                    .padding(horizontal = 18.dp, vertical = 6.dp),
                contentAlignment = Alignment.Center,
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxSize()
                        .ios27LiquidGlass(shape = CircleShape, dark = dark, elevation = 12.dp)
                        .padding(horizontal = 5.dp, vertical = 5.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    items.forEachIndexed { idx, label ->
                        val selected = idx == selectedIndex
                        val color = if (selected) Ios27Palette.SystemBlue else inactiveFg
                        val iconName = itemIcons.getOrNull(idx) ?: ""
                        Column(
                            modifier = Modifier
                                .weight(1f)
                                .fillMaxHeight()
                                .clip(CircleShape)
                                .background(if (selected) pillBg else Color.Transparent)
                                .then(
                                    if (selected) {
                                        Modifier.border(0.6.dp, Ios27Palette.specularRimBrush(dark), CircleShape)
                                    } else Modifier
                                )
                                .clickable { onSelect(idx) },
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center,
                        ) {
                            DrawTabGlyph(name = iconName, color = color)
                            Spacer(Modifier.height(2.dp))
                            Text(
                                text = label,
                                color = color,
                                fontSize = 11.sp,
                                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Alert Dialog (iOS 27 Liquid Glass Modal vs Material 3 AlertDialog)

@Composable
internal fun RenderDualStyleAlert(
    uiStyle: AndroidUIStyle,
    title: String,
    message: String,
    actions: List<AlertActionItem>,
    onAction: (Int) -> Unit,
    onDismiss: () -> Unit,
) {
    when (uiStyle) {
        AndroidUIStyle.ANDROID_NATIVE -> {
            val cancelIdx = actions.indexOfFirst { it.role == "cancel" }
            val confirmIdx = actions.indexOfFirst { it.role != "cancel" }.takeIf { it >= 0 } ?: 0
            AlertDialog(
                onDismissRequest = onDismiss,
                title = if (title.isNotEmpty()) { { Text(title) } } else null,
                text = if (message.isNotEmpty()) { { Text(message) } } else null,
                confirmButton = {
                    if (actions.size <= 2) {
                        val act = actions[confirmIdx]
                        TextButton(
                            onClick = { onAction(confirmIdx) },
                            enabled = act.enabled,
                        ) {
                            Text(
                                act.title,
                                color = if (act.role == "destructive") MaterialTheme.colorScheme.error else Color.Unspecified,
                            )
                        }
                    } else {
                        Column(horizontalAlignment = Alignment.End) {
                            actions.forEachIndexed { idx, act ->
                                TextButton(
                                    onClick = { onAction(idx) },
                                    enabled = act.enabled,
                                ) {
                                    Text(
                                        act.title,
                                        color = if (act.role == "destructive") MaterialTheme.colorScheme.error else Color.Unspecified,
                                    )
                                }
                            }
                        }
                    }
                },
                dismissButton = if (actions.size == 2 && cancelIdx >= 0 && cancelIdx != confirmIdx) {
                    {
                        val act = actions[cancelIdx]
                        TextButton(onClick = { onAction(cancelIdx) }, enabled = act.enabled) {
                            Text(act.title)
                        }
                    }
                } else null,
            )
        }

        AndroidUIStyle.IOS -> {
            val dark = isSystemInDarkTheme()
            val surface = if (dark) Ios27Palette.AlertSurfaceDark else Ios27Palette.AlertSurfaceLight
            val btnFill = if (dark) Ios27Palette.AlertButtonDark else Ios27Palette.AlertButtonLight
            val titleColor = if (dark) Color.White else Color.Black
            val msgColor = if (dark) Color(0xCCEBEBF5) else Color(0xB83C3C43)
            val sideBySide = actions.size == 2 && actions.all { it.title.length <= 14 }
            val shape = RoundedCornerShape(28.dp)

            Dialog(
                onDismissRequest = onDismiss,
                properties = DialogProperties(usePlatformDefaultWidth = false),
            ) {
                Box(
                    modifier = Modifier
                        .widthIn(min = 276.dp, max = 316.dp)
                        .ios27LiquidGlass(shape = shape, dark = dark, elevation = 24.dp, fillOverride = surface)
                        .padding(horizontal = 20.dp, vertical = 22.dp),
                ) {
                    Column(
                        horizontalAlignment = Alignment.Start,
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        if (title.isNotEmpty()) {
                            Text(
                                text = title,
                                color = titleColor,
                                fontSize = 17.sp,
                                fontWeight = FontWeight.SemiBold,
                            )
                        }
                        if (message.isNotEmpty()) {
                            Text(
                                text = message,
                                color = msgColor,
                                fontSize = 14.sp,
                                lineHeight = 19.sp,
                            )
                        }
                        Spacer(Modifier.height(6.dp))
                        if (sideBySide) {
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(10.dp),
                            ) {
                                actions.forEachIndexed { idx, act ->
                                    IosAlertPillButton(
                                        action = act,
                                        fill = btnFill,
                                        dark = dark,
                                        modifier = Modifier.weight(1f),
                                        onClick = { onAction(idx) },
                                    )
                                }
                            }
                        } else {
                            Column(
                                modifier = Modifier.fillMaxWidth(),
                                verticalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                actions.forEachIndexed { idx, act ->
                                    IosAlertPillButton(
                                        action = act,
                                        fill = btnFill,
                                        dark = dark,
                                        modifier = Modifier.fillMaxWidth(),
                                        onClick = { onAction(idx) },
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun IosAlertPillButton(
    action: AlertActionItem,
    fill: Color,
    dark: Boolean,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed && action.enabled) 0.96f else 1f,
        animationSpec = spring(dampingRatio = 0.72f, stiffness = 500f),
        label = "ios27AlertBtnScale",
    )
    val textColor = when {
        !action.enabled -> (if (dark) Color.White else Color.Black).copy(alpha = 0.35f)
        action.role == "destructive" -> Ios27Palette.SystemRed
        action.role == "cancel" -> if (dark) Color.White else Color.Black
        else -> if (dark) Color.White else Color.Black
    }
    Box(
        modifier = modifier
            .height(44.dp)
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
            }
            .clip(CircleShape)
            .background(fill)
            .border(0.6.dp, Ios27Palette.specularRimBrush(dark), CircleShape)
            .clickable(
                enabled = action.enabled,
                interactionSource = interactionSource,
                indication = null,
                onClick = onClick,
            )
            .padding(horizontal = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = action.title,
            color = textColor,
            fontSize = 16.sp,
            fontWeight = if (action.role == "cancel") FontWeight.Medium else FontWeight.SemiBold,
            textAlign = TextAlign.Center,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

// MARK: - Crisp Built-In Glyphs

@Composable
private fun DrawChevronBackIcon(color: Color) {
    Canvas(modifier = Modifier.size(11.dp, 18.dp)) {
        val stroke = 2.2.dp.toPx()
        drawLine(color, Offset(size.width * 0.76f, size.height * 0.14f), Offset(size.width * 0.22f, size.height * 0.5f), stroke, StrokeCap.Round)
        drawLine(color, Offset(size.width * 0.22f, size.height * 0.5f), Offset(size.width * 0.76f, size.height * 0.86f), stroke, StrokeCap.Round)
    }
}

@Composable
private fun DrawArrowBackIcon(color: Color) {
    Canvas(modifier = Modifier.size(20.dp)) {
        val stroke = 2.dp.toPx()
        drawLine(color, Offset(size.width * 0.82f, size.height * 0.5f), Offset(size.width * 0.22f, size.height * 0.5f), stroke, StrokeCap.Round)
        drawLine(color, Offset(size.width * 0.48f, size.height * 0.22f), Offset(size.width * 0.2f, size.height * 0.5f), stroke, StrokeCap.Round)
        drawLine(color, Offset(size.width * 0.2f, size.height * 0.5f), Offset(size.width * 0.48f, size.height * 0.78f), stroke, StrokeCap.Round)
    }
}

@Composable
private fun DrawTabGlyph(name: String, color: Color) {
    Canvas(modifier = Modifier.size(20.dp)) {
        val sw = 1.8.dp.toPx()
        val w = size.width
        val h = size.height
        when {
            name.contains("house") -> {
                drawLine(color, Offset(w * 0.15f, h * 0.48f), Offset(w * 0.5f, h * 0.15f), sw, StrokeCap.Round)
                drawLine(color, Offset(w * 0.5f, h * 0.15f), Offset(w * 0.85f, h * 0.48f), sw, StrokeCap.Round)
                drawLine(color, Offset(w * 0.24f, h * 0.44f), Offset(w * 0.24f, h * 0.85f), sw, StrokeCap.Round)
                drawLine(color, Offset(w * 0.76f, h * 0.44f), Offset(w * 0.76f, h * 0.85f), sw, StrokeCap.Round)
                drawLine(color, Offset(w * 0.24f, h * 0.85f), Offset(w * 0.76f, h * 0.85f), sw, StrokeCap.Round)
            }
            name.contains("magnifyingglass") -> {
                drawCircle(color, radius = w * 0.28f, center = Offset(w * 0.43f, h * 0.43f), style = Stroke(sw))
                drawLine(color, Offset(w * 0.64f, h * 0.64f), Offset(w * 0.86f, h * 0.86f), sw, StrokeCap.Round)
            }
            name.contains("person") -> {
                drawCircle(color, radius = w * 0.18f, center = Offset(w * 0.5f, h * 0.3f), style = Stroke(sw))
                drawArc(
                    color = color,
                    startAngle = 200f,
                    sweepAngle = 140f,
                    useCenter = false,
                    topLeft = Offset(w * 0.16f, h * 0.54f),
                    size = Size(w * 0.68f, h * 0.55f),
                    style = Stroke(sw, cap = StrokeCap.Round),
                )
            }
            else -> {
                drawCircle(color, radius = w * 0.3f, center = Offset(w * 0.5f, h * 0.5f), style = Stroke(sw))
            }
        }
    }
}

// MARK: - Divider (Material 3 HorizontalDivider vs iOS 27 Hairline)

@Composable
internal fun RenderDualStyleDivider(
    uiStyle: AndroidUIStyle,
    modifier: Modifier,
) {
    when (uiStyle) {
        AndroidUIStyle.ANDROID_NATIVE -> {
            Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                HorizontalDivider()
            }
        }

        AndroidUIStyle.IOS -> {
            val dark = isSystemInDarkTheme()
            val color = if (dark) Color(0x28FFFFFF) else Color(0x1E3C3C43)
            Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                HorizontalDivider(thickness = 0.5.dp, color = color)
            }
        }
    }
}

// MARK: - Grouped Section Card (Material 3 OutlinedCard)

@Composable
internal fun RenderMaterial3SectionCard(modifier: Modifier) {
    OutlinedCard(
        modifier = modifier.fillMaxSize(),
        shape = MaterialTheme.shapes.large,
        colors = CardDefaults.outlinedCardColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
        ),
    ) {}
}

// MARK: - Checkbox (Material 3 Checkbox vs iOS 27 Circular Checkmark)

@Composable
internal fun RenderDualStyleCheckbox(
    uiStyle: AndroidUIStyle,
    checked: Boolean,
    enabled: Boolean,
    tint: Color?,
    modifier: Modifier,
    onCheckedChange: (Boolean) -> Unit,
) {
    when (uiStyle) {
        AndroidUIStyle.ANDROID_NATIVE -> {
            Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Checkbox(
                    checked = checked,
                    onCheckedChange = onCheckedChange,
                    enabled = enabled,
                )
            }
        }

        AndroidUIStyle.IOS -> {
            val dark = isSystemInDarkTheme()
            val accent = tint ?: Ios27Palette.SystemBlue
            val borderCol = if (dark) Color(0x66EBEBF5) else Color(0x4D3C3C43)
            Box(
                modifier = modifier
                    .fillMaxSize()
                    .clickable(
                        enabled = enabled,
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) { onCheckedChange(!checked) },
                contentAlignment = Alignment.Center,
            ) {
                Canvas(modifier = Modifier.size(22.dp)) {
                    if (checked) {
                        drawCircle(color = accent.copy(alpha = if (enabled) 1f else 0.4f))
                        val sw = 2.dp.toPx()
                        drawLine(
                            Color.White,
                            Offset(size.width * 0.27f, size.height * 0.52f),
                            Offset(size.width * 0.44f, size.height * 0.69f),
                            sw,
                            StrokeCap.Round,
                        )
                        drawLine(
                            Color.White,
                            Offset(size.width * 0.44f, size.height * 0.69f),
                            Offset(size.width * 0.74f, size.height * 0.34f),
                            sw,
                            StrokeCap.Round,
                        )
                    } else {
                        drawCircle(color = borderCol, style = Stroke(width = 1.6.dp.toPx()))
                    }
                }
            }
        }
    }
}

// MARK: - Menu / Picker(.menu) (Material 3 DropdownMenu vs iOS 27 Glass Menu)

@Composable
internal fun RenderDualStyleMenu(
    uiStyle: AndroidUIStyle,
    title: String,
    items: List<String>,
    selectedIndex: Int,
    enabled: Boolean,
    tint: Color?,
    modifier: Modifier,
    onSelect: (Int) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val displayTitle = items.getOrNull(selectedIndex) ?: title

    Box(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.CenterStart) {
        when (uiStyle) {
            AndroidUIStyle.ANDROID_NATIVE -> {
                OutlinedButton(
                    onClick = { if (enabled) expanded = true },
                    enabled = enabled,
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    Text(displayTitle, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }

            AndroidUIStyle.IOS -> {
                val dark = isSystemInDarkTheme()
                val accent = tint ?: Ios27Palette.SystemBlue
                val bg = if (dark) Ios27Palette.FillTertiaryDark else Ios27Palette.FillTertiaryLight
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .clip(CircleShape)
                        .background(bg)
                        .border(0.6.dp, Ios27Palette.specularRimBrush(dark), CircleShape)
                        .clickable(enabled = enabled) { expanded = true }
                        .padding(horizontal = 12.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = "$displayTitle ⌄",
                        color = accent.copy(alpha = if (enabled) 1f else 0.4f),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }

        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            items.forEachIndexed { idx, label ->
                DropdownMenuItem(
                    text = {
                        Text(
                            text = if (idx == selectedIndex) "✓  $label" else label,
                            fontWeight = if (idx == selectedIndex) FontWeight.SemiBold else FontWeight.Normal,
                        )
                    },
                    onClick = {
                        expanded = false
                        onSelect(idx)
                    },
                )
            }
        }
    }
}

// MARK: - Sheet (Material 3 ModalBottomSheet vs iOS 27 Sheet)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun RenderDualStyleSheet(
    uiStyle: AndroidUIStyle,
    onDismiss: () -> Unit,
    content: @Composable () -> Unit,
) {
    val dark = isSystemInDarkTheme()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val shape = when (uiStyle) {
        AndroidUIStyle.ANDROID_NATIVE -> MaterialTheme.shapes.extraLarge
        AndroidUIStyle.IOS -> RoundedCornerShape(topStart = 36.dp, topEnd = 36.dp)
    }
    val containerColor = when (uiStyle) {
        AndroidUIStyle.ANDROID_NATIVE -> MaterialTheme.colorScheme.surfaceContainerLow
        AndroidUIStyle.IOS -> if (dark) Color(0xFF1C1C1E) else Color(0xFFF2F2F7)
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        shape = shape,
        containerColor = containerColor,
    ) {
        content()
    }
}
