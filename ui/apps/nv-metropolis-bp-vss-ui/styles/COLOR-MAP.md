# Color Rebrand Mapping

## Brand Tokens

| Token        | Hex       | RGB              |
|--------------|-----------|------------------|
| primary      | #2F5FA7   | 47, 95, 167      |
| primaryDark  | #1B2A41   | 27, 42, 65       |
| accent       | #F36F21   | 243, 111, 33     |
| accentSoft   | #F89A4B   | 248, 154, 75     |
| success      | #168C47   | 22, 140, 71      |
| successSoft  | #63C192   | 99, 193, 146     |
| background   | #FFFFFF   | 255, 255, 255    |
| surface      | #F8FAFC   | 248, 250, 252    |
| textPrimary  | #222222   | 34, 34, 34       |
| textSecondary| #5C5C5C   | 92, 92, 92       |
| border       | #E5E7EB   | 229, 231, 235    |

## Tailwind → Brand Mapping (opacity-shaded from base token)

### Blue → Primary (#2F5FA7 / rgb 47,95,167)

| Tailwind Class | Opacity | Computed Hex | Usage |
|----------------|---------|-------------|-------|
| blue-50        | 8%      | #F0F4F9     | light bg tint |
| blue-100       | 15%     | #E2EAF3     | info bg, badges |
| blue-200       | 25%     | #CBDAEA     | light borders |
| blue-300       | 40%     | #AEC3DB     | borders |
| blue-400       | 60%     | #829FBF     | text muted, ring |
| blue-500       | 80%     | #5880B3     | text, ring |
| blue-600       | 100%    | #2F5FA7     | primary buttons, bg |
| blue-700       | 100%    | #264D89     | hover states (darken 15%) |
| blue-800       | 100%    | #1B2A41     | primaryDark |
| blue-900       | 100%    | #152235     | deep text |

### Orange → Accent (#F36F21 / rgb 243,111,33)

| Tailwind Class | Opacity | Computed Hex | Usage |
|----------------|---------|-------------|-------|
| orange-50      | 8%      | #FEF5EF     | light bg tint |
| orange-100     | 15%     | #FDE8DA     | warning bg |
| orange-300     | 50%     | #F9B790     | text soft |
| orange-400     | 70%     | #F69658     | text, border |
| orange-500     | 100%    | #F36F21     | accent badges |
| orange-600     | 100%    | #DA6219     | darker accent text |
| orange-700     | 100%    | #B85215     | dark text |
| orange-900     | 100%    | #7A3710     | dark mode bg tint |

### Green → Success (#168C47 / rgb 22,140,71)

| Tailwind Class | Opacity | Computed Hex | Usage |
|----------------|---------|-------------|-------|
| green-50       | 8%      | #F0F8F3     | light bg tint |
| green-100      | 15%     | #DFF0E6     | success bg |
| green-200      | 25%     | #C3E2CF     | light borders |
| green-300      | 40%     | #9DCFB0     | borders |
| green-400      | 60%     | #63C192     | successSoft text |
| green-500      | 80%     | #3AA464     | text, fill, badges |
| green-600      | 100%    | #168C47     | success buttons |
| green-700      | 100%    | #12733A     | hover/dark text |
| green-900      | 100%    | #0A4421     | dark mode bg tint |

### NVIDIA Green (#76b900) → Primary (#2F5FA7)

This hex is hardcoded in 16 component files. Replace with `var(--brand-primary)`.
Dark variant #5a8c00/#5a8f00 → `var(--brand-primary-dark)` or #264D89.
Light variant #91c438 → `var(--brand-primary-soft)` or #5880B3.

### Dark-mode chat backgrounds (unchanged — neutral palette)

| Hex     | Keep as-is | Reason |
|---------|------------|--------|
| #343541 | yes        | chat bg (neutral) |
| #202123 | yes        | deep bg (neutral) |
| #444654 | yes        | assistant msg bg |
| #40414F | yes        | input bg |

### Error reds (unchanged)

| Hex     | Keep as-is | Reason |
|---------|------------|--------|
| #dc2626 | yes        | error (red-600) |
| #ef4444 | yes        | error (red-500) |
| #f44336 | yes        | error (material red) |

### Neutral grays (unchanged)

All gray-* Tailwind classes remain untouched.
