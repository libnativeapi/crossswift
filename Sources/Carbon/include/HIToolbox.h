#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// Apple HIToolbox virtual key codes (Events.h) — untyped C enums import as `Int` in Swift,
// matching macOS `Carbon.HIToolbox` one-for-one.
enum {
  kVK_ANSI_A                    = 0x00,
  kVK_ANSI_S                    = 0x01,
  kVK_ANSI_D                    = 0x02,
  kVK_ANSI_F                    = 0x03,
  kVK_ANSI_H                    = 0x04,
  kVK_ANSI_G                    = 0x05,
  kVK_ANSI_Z                    = 0x06,
  kVK_ANSI_X                    = 0x07,
  kVK_ANSI_C                    = 0x08,
  kVK_ANSI_V                    = 0x09,
  kVK_ANSI_B                    = 0x0B,
  kVK_ANSI_Q                    = 0x0C,
  kVK_ANSI_W                    = 0x0D,
  kVK_ANSI_E                    = 0x0E,
  kVK_ANSI_R                    = 0x0F,
  kVK_ANSI_Y                    = 0x10,
  kVK_ANSI_T                    = 0x11,
  kVK_ANSI_1                    = 0x12,
  kVK_ANSI_2                    = 0x13,
  kVK_ANSI_3                    = 0x14,
  kVK_ANSI_4                    = 0x15,
  kVK_ANSI_6                    = 0x16,
  kVK_ANSI_5                    = 0x17,
  kVK_ANSI_Equal                = 0x18,
  kVK_ANSI_9                    = 0x19,
  kVK_ANSI_7                    = 0x1A,
  kVK_ANSI_Minus                = 0x1B,
  kVK_ANSI_8                    = 0x1C,
  kVK_ANSI_0                    = 0x1D,
  kVK_ANSI_RightBracket         = 0x1E,
  kVK_ANSI_O                    = 0x1F,
  kVK_ANSI_U                    = 0x20,
  kVK_ANSI_LeftBracket          = 0x21,
  kVK_ANSI_I                    = 0x22,
  kVK_ANSI_P                    = 0x23,
  kVK_ANSI_L                    = 0x25,
  kVK_ANSI_J                    = 0x26,
  kVK_ANSI_Quote                = 0x27,
  kVK_ANSI_K                    = 0x28,
  kVK_ANSI_Semicolon            = 0x29,
  kVK_ANSI_Backslash            = 0x2A,
  kVK_ANSI_Comma                = 0x2B,
  kVK_ANSI_Slash                = 0x2C,
  kVK_ANSI_N                    = 0x2D,
  kVK_ANSI_M                    = 0x2E,
  kVK_ANSI_Period               = 0x2F,
  kVK_ANSI_Grave                = 0x32,
  kVK_ANSI_KeypadDecimal        = 0x41,
  kVK_ANSI_KeypadMultiply       = 0x43,
  kVK_ANSI_KeypadPlus           = 0x45,
  kVK_ANSI_KeypadClear          = 0x47,
  kVK_ANSI_KeypadDivide         = 0x4B,
  kVK_ANSI_KeypadEnter          = 0x4C,
  kVK_ANSI_KeypadMinus          = 0x4E,
  kVK_ANSI_KeypadEquals         = 0x51,
  kVK_ANSI_Keypad0              = 0x52,
  kVK_ANSI_Keypad1              = 0x53,
  kVK_ANSI_Keypad2              = 0x54,
  kVK_ANSI_Keypad3              = 0x55,
  kVK_ANSI_Keypad4              = 0x56,
  kVK_ANSI_Keypad5              = 0x57,
  kVK_ANSI_Keypad6              = 0x58,
  kVK_ANSI_Keypad7              = 0x59,
  kVK_ANSI_Keypad8              = 0x5B,
  kVK_ANSI_Keypad9              = 0x5C
};

enum {
  kVK_Return                    = 0x24,
  kVK_Tab                       = 0x30,
  kVK_Space                     = 0x31,
  kVK_Delete                    = 0x33,
  kVK_Escape                    = 0x35,
  kVK_Command                   = 0x37,
  kVK_Shift                     = 0x38,
  kVK_CapsLock                  = 0x39,
  kVK_Option                    = 0x3A,
  kVK_Control                   = 0x3B,
  kVK_RightCommand              = 0x36,
  kVK_RightShift                = 0x3C,
  kVK_RightOption               = 0x3D,
  kVK_RightControl              = 0x3E,
  kVK_Function                  = 0x3F,
  kVK_F17                       = 0x40,
  kVK_VolumeUp                  = 0x48,
  kVK_VolumeDown                = 0x49,
  kVK_Mute                      = 0x4A,
  kVK_F18                       = 0x4F,
  kVK_F19                       = 0x50,
  kVK_F20                       = 0x5A,
  kVK_F5                        = 0x60,
  kVK_F6                        = 0x61,
  kVK_F7                        = 0x62,
  kVK_F3                        = 0x63,
  kVK_F8                        = 0x64,
  kVK_F9                        = 0x65,
  kVK_F11                       = 0x67,
  kVK_F13                       = 0x69,
  kVK_F16                       = 0x6A,
  kVK_F14                       = 0x6B,
  kVK_F10                       = 0x6D,
  kVK_ContextualMenu            = 0x6E,
  kVK_F12                       = 0x6F,
  kVK_F15                       = 0x71,
  kVK_Help                      = 0x72,
  kVK_Home                      = 0x73,
  kVK_PageUp                    = 0x74,
  kVK_ForwardDelete             = 0x75,
  kVK_F4                        = 0x76,
  kVK_End                       = 0x77,
  kVK_F2                        = 0x78,
  kVK_PageDown                  = 0x79,
  kVK_F1                        = 0x7A,
  kVK_LeftArrow                 = 0x7B,
  kVK_RightArrow                = 0x7C,
  kVK_DownArrow                 = 0x7D,
  kVK_UpArrow                   = 0x7E,
  kVK_ISO_Section               = 0x0A,
  kVK_JIS_Yen                   = 0x5D,
  kVK_JIS_Underscore            = 0x5E,
  kVK_JIS_KeypadComma           = 0x5F,
  kVK_JIS_Eisu                  = 0x66,
  kVK_JIS_Kana                  = 0x68
};

// Carbon modifier key masks (Events.h)
enum {
  cmdKeyBit                     = 8,
  shiftKeyBit                   = 9,
  alphaLockBit                  = 10,
  optionKeyBit                  = 11,
  controlKeyBit                 = 12,
  rightShiftKeyBit              = 13,
  rightOptionKeyBit             = 14,
  rightControlKeyBit            = 15
};

enum {
  cmdKey                        = 1 << cmdKeyBit,
  shiftKey                      = 1 << shiftKeyBit,
  alphaLock                     = 1 << alphaLockBit,
  optionKey                     = 1 << optionKeyBit,
  controlKey                    = 1 << controlKeyBit,
  rightShiftKey                 = 1 << rightShiftKeyBit,
  rightOptionKey                = 1 << rightOptionKeyBit,
  rightControlKey               = 1 << rightControlKeyBit,
  kEventKeyModifierFnMask       = 1 << 17
};

typedef uint32_t OSType;
typedef int32_t OSStatus;
typedef uint32_t OptionBits;
typedef uint16_t UniChar;
static const OSStatus noErr = 0;
static const OSStatus errSecAllocate = -108;
enum {
  eventNotHandledErr = -9874
};

typedef struct UCKeyboardLayout {
  uint16_t keyLayoutHeaderFormat;
} UCKeyboardLayout;

enum {
  kUCKeyActionDisplay = 3,
  kUCKeyTranslateNoDeadKeysBit = 0
};

static inline uint8_t LMGetKbdType(void) { return 40; }

static inline OSStatus UCKeyTranslate(
  const UCKeyboardLayout *keyLayoutPtr,
  uint16_t virtualKeyCode,
  uint16_t keyAction,
  uint32_t modifierKeyState,
  uint32_t keyboardType,
  OptionBits keyTranslateOptions,
  uint32_t *deadKeyState,
  size_t maxStringLength,
  size_t *actualStringLength,
  uint16_t *unicodeString
) {
  (void)keyLayoutPtr; (void)keyAction; (void)keyboardType; (void)keyTranslateOptions;
  if (deadKeyState) *deadKeyState = 0;
  bool shift = ((modifierKeyState << 8) & shiftKey) != 0;
  uint16_t ch = 0;
  switch (virtualKeyCode) {
    case kVK_ANSI_A: ch = shift ? 'A' : 'a'; break;
    case kVK_ANSI_B: ch = shift ? 'B' : 'b'; break;
    case kVK_ANSI_C: ch = shift ? 'C' : 'c'; break;
    case kVK_ANSI_D: ch = shift ? 'D' : 'd'; break;
    case kVK_ANSI_E: ch = shift ? 'E' : 'e'; break;
    case kVK_ANSI_F: ch = shift ? 'F' : 'f'; break;
    case kVK_ANSI_G: ch = shift ? 'G' : 'g'; break;
    case kVK_ANSI_H: ch = shift ? 'H' : 'h'; break;
    case kVK_ANSI_I: ch = shift ? 'I' : 'i'; break;
    case kVK_ANSI_J: ch = shift ? 'J' : 'j'; break;
    case kVK_ANSI_K: ch = shift ? 'K' : 'k'; break;
    case kVK_ANSI_L: ch = shift ? 'L' : 'l'; break;
    case kVK_ANSI_M: ch = shift ? 'M' : 'm'; break;
    case kVK_ANSI_N: ch = shift ? 'N' : 'n'; break;
    case kVK_ANSI_O: ch = shift ? 'O' : 'o'; break;
    case kVK_ANSI_P: ch = shift ? 'P' : 'p'; break;
    case kVK_ANSI_Q: ch = shift ? 'Q' : 'q'; break;
    case kVK_ANSI_R: ch = shift ? 'R' : 'r'; break;
    case kVK_ANSI_S: ch = shift ? 'S' : 's'; break;
    case kVK_ANSI_T: ch = shift ? 'T' : 't'; break;
    case kVK_ANSI_U: ch = shift ? 'U' : 'u'; break;
    case kVK_ANSI_V: ch = shift ? 'V' : 'v'; break;
    case kVK_ANSI_W: ch = shift ? 'W' : 'w'; break;
    case kVK_ANSI_X: ch = shift ? 'X' : 'x'; break;
    case kVK_ANSI_Y: ch = shift ? 'Y' : 'y'; break;
    case kVK_ANSI_Z: ch = shift ? 'Z' : 'z'; break;
    case kVK_ANSI_0: ch = shift ? ')' : '0'; break;
    case kVK_ANSI_1: ch = shift ? '!' : '1'; break;
    case kVK_ANSI_2: ch = shift ? '@' : '2'; break;
    case kVK_ANSI_3: ch = shift ? '#' : '3'; break;
    case kVK_ANSI_4: ch = shift ? '$' : '4'; break;
    case kVK_ANSI_5: ch = shift ? '%' : '5'; break;
    case kVK_ANSI_6: ch = shift ? '^' : '6'; break;
    case kVK_ANSI_7: ch = shift ? '&' : '7'; break;
    case kVK_ANSI_8: ch = shift ? '*' : '8'; break;
    case kVK_ANSI_9: ch = shift ? '(' : '9'; break;
    case kVK_ANSI_Minus: ch = shift ? '_' : '-'; break;
    case kVK_ANSI_Equal: ch = shift ? '+' : '='; break;
    case kVK_ANSI_LeftBracket: ch = shift ? '{' : '['; break;
    case kVK_ANSI_RightBracket: ch = shift ? '}' : ']'; break;
    case kVK_ANSI_Backslash: ch = shift ? '|' : '\\'; break;
    case kVK_ANSI_Semicolon: ch = shift ? ':' : ';'; break;
    case kVK_ANSI_Quote: ch = shift ? '"' : '\''; break;
    case kVK_ANSI_Comma: ch = shift ? '<' : ','; break;
    case kVK_ANSI_Period: ch = shift ? '>' : '.'; break;
    case kVK_ANSI_Slash: ch = shift ? '?' : '/'; break;
    case kVK_ANSI_Grave: ch = shift ? '~' : '`'; break;
    case kVK_Space: ch = ' '; break;
    default: break;
  }
  if (ch != 0 && maxStringLength >= 1 && unicodeString) {
    unicodeString[0] = ch;
    if (actualStringLength) *actualStringLength = 1;
    return noErr;
  }
  if (actualStringLength) *actualStringLength = 0;
  return -1;
}

enum {
  kEventParamDirectObject = 0x2D2D2D2D, // '----'
  kEventParamKeyCode      = 0x6B636F64, // 'kcod'
  kEventParamKeyModifiers = 0x6B6D6F64, // 'kmod'
  kEventClassKeyboard     = 0x6B657962, // 'keyb'
  kEventRawKeyDown        = 1,
  kEventRawKeyRepeat      = 2,
  kEventRawKeyUp          = 3,
  kEventRawKeyModifiersChanged = 4,
  kEventHotKeyPressed     = 5,
  kEventHotKeyReleased    = 6
};

static const uint32_t typeEventHotKeyID = 0x686B6964; // 'hkid'
static const uint32_t typeUInt32        = 0x6D61676E; // 'magn'

typedef struct OpaqueEventTargetRef *EventTargetRef;
typedef struct OpaqueEventHandlerCallRef *EventHandlerCallRef;
typedef struct OpaqueEventRef *EventRef;
typedef struct OpaqueEventHotKeyRef *EventHotKeyRef;
typedef struct OpaqueEventHandlerRef *EventHandlerRef;

typedef struct EventHotKeyID {
  OSType signature;
  uint32_t id;
} EventHotKeyID;

typedef struct EventTypeSpec {
  OSType eventClass;
  uint32_t eventKind;
} EventTypeSpec;

typedef OSStatus (*EventHandlerProcPtr)(
  EventHandlerCallRef inHandlerCallRef,
  EventRef inEvent,
  void *inUserData
);
typedef EventHandlerProcPtr EventHandlerUPP;

EventTargetRef GetEventDispatcherTarget(void);

OSStatus InstallEventHandler(
  EventTargetRef inTarget,
  EventHandlerUPP inHandler,
  intptr_t inNumTypes,
  const EventTypeSpec *inList,
  void *inUserData,
  EventHandlerRef *outRef
);

static inline OSStatus AddEventTypesToHandler(
  EventHandlerRef inHandlerRef,
  intptr_t inNumTypes,
  const EventTypeSpec *inList
) {
  (void)inHandlerRef; (void)inNumTypes; (void)inList;
  return noErr;
}

static inline OSStatus RemoveEventTypesFromHandler(
  EventHandlerRef inHandlerRef,
  intptr_t inNumTypes,
  const EventTypeSpec *inList
) {
  (void)inHandlerRef; (void)inNumTypes; (void)inList;
  return noErr;
}

OSStatus RegisterEventHotKey(
  uint32_t inHotKeyCode,
  uint32_t inHotKeyModifiers,
  EventHotKeyID inHotKeyID,
  EventTargetRef inTarget,
  uint32_t inOptions,
  EventHotKeyRef *outRef
);

OSStatus UnregisterEventHotKey(EventHotKeyRef inHotKey);

OSStatus GetEventParameter(
  EventRef inEvent,
  uint32_t inName,
  uint32_t inDesiredType,
  uint32_t *outActualType,
  intptr_t inBufferSize,
  intptr_t *outActualSize,
  void *outData
);

uint32_t GetEventKind(EventRef inEvent);

typedef OSStatus (*CrossSwiftRegisterHotKeyFn)(
  uint32_t keyCode,
  uint32_t modifiers,
  EventHotKeyID hotKeyID,
  void **outHandle
);
typedef OSStatus (*CrossSwiftUnregisterHotKeyFn)(void *handle);

void _crossswift_carbon_set_hotkey_hooks(
  CrossSwiftRegisterHotKeyFn registerFn,
  CrossSwiftUnregisterHotKeyFn unregisterFn
);

void _crossswift_carbon_dispatch_hotkey(
  OSType signature,
  uint32_t id,
  uint32_t kind
);

static inline bool IsSecureEventInputEnabled(void) {
  return false;
}
