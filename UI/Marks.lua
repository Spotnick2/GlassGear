------------------------------------------------------------
-- UI/Marks.lua - the look of an upgrade mark, shared by the bag (GG-109) and
-- loot (GG-111) markers.
--
--   green: a current-spec upgrade - Blizzard's own filled upgrade arrow
--          (atlas "bags-greenarrow", EquipmentFlyout.xml:10);
--   amber: the same arrow drawn as an amber outline (the arrow desaturated and
--          tinted, with a dark inner copy), so the two differ by shape too.
--
--   Marks.New(parent) -> mark      our own child frame; never call in combat
--   Marks.Attach(mark, button)     (re)parent and anchor to a Blizzard button
--   Marks.Set(mark, kind)          "green" | "amber" shows it, nil hides it
--
-- Re-parenting and anchoring our own unprotected frame is combat-safe; only
-- creating one is kept out of combat (the GlassPearls BagMarks rule).
------------------------------------------------------------

local GG = GlassGear
local Marks = {}
GG.Marks = Marks

Marks.ATLAS = "bags-greenarrow"
Marks.SIZE = 14
Marks.STYLE = {
    green = { color = { 1, 1, 1, 1 }, fallback = { 0.25, 1, 0.25, 0.95 } },
    amber = { color = { 1, 0.72, 0.15, 1 }, desaturate = true, inner = { 0.08, 0.05, 0, 0.9 },
        fallback = { 1, 0.72, 0.15, 0.95 } },
}

local atlasOK

function Marks.Attach(m, button)
    if m:GetParent() ~= button then m:SetParent(button) end
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
end

function Marks.New(parent)
    local m = CreateFrame("Frame", nil, parent)
    m:SetSize(Marks.SIZE, Marks.SIZE)
    m:EnableMouse(false)
    m.fill = m:CreateTexture(nil, "OVERLAY")
    m.fill:SetAllPoints(m)
    -- The inner cut-out that turns the amber arrow into an outline.
    m.inner = m:CreateTexture(nil, "OVERLAY", nil, 1)
    m.inner:SetPoint("TOPLEFT", m, "TOPLEFT", 3, -3)
    m.inner:SetPoint("BOTTOMRIGHT", m, "BOTTOMRIGHT", -3, 3)
    if atlasOK == nil then atlasOK = GG.Compat.AtlasKnown(Marks.ATLAS) end
    if atlasOK then
        m.fill:SetAtlas(Marks.ATLAS)
        m.inner:SetAtlas(Marks.ATLAS)
    end
    if parent then m:SetPoint("TOPLEFT", parent, "TOPLEFT", 1, -1) end
    return m
end

local function paint(m, kind)
    if m.kind == kind then return end
    m.kind = kind
    local s = Marks.STYLE[kind]
    if atlasOK then
        m.fill:SetDesaturated(s.desaturate == true)
        m.fill:SetVertexColor(s.color[1], s.color[2], s.color[3], s.color[4])
        if s.inner then
            m.inner:SetDesaturated(true)
            m.inner:SetVertexColor(s.inner[1], s.inner[2], s.inner[3], s.inner[4])
            m.inner:Show()
        else
            m.inner:Hide()
        end
    else
        m.fill:SetColorTexture(s.fallback[1], s.fallback[2], s.fallback[3], s.fallback[4])
        if s.inner then
            m.inner:SetColorTexture(s.inner[1], s.inner[2], s.inner[3], s.inner[4])
            m.inner:Show()
        else
            m.inner:Hide()
        end
    end
end

function Marks.Set(m, kind)
    if kind then
        paint(m, kind)
        m:Show()
    else
        m:Hide()
    end
end

return Marks
