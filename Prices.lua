-- Prix partagés : scan HdV de Scout (persisté pour les objets utiles), Auctionator en secours,
-- prix marchands (achat vu en jeu, vente d'après la base de butin ou le client).
local _, ns = ...
local Prices = {}
ns.Prices = Prices

local AH_CUT = 0.05
local session = {}   -- tous les objets vus au dernier scan de cette session : [itemID] = { p, q }
local valueCache = {}

-- Prix d'achat marchand de base (cuivre) pour les composants courants.
local VENDOR_SEED = {
    [2320] = 10, [2321] = 100, [4291] = 500, [8343] = 2000, [14341] = 5000,   -- fils
    [4289] = 50, [2324] = 25, [2604] = 50, [2605] = 100, [4340] = 350, [2325] = 1000,   -- sel, teintures
}

function Prices.SetSession(seen) session = seen Prices.ResetCache() end
function Prices.ResetCache() wipe(valueCache) end

local function Auctionator_(id)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not (api and api.GetAuctionPriceByItemID) then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, "Scout", id)
    return ok and price or nil
end

function Prices.HasAuctionator() return (Auctionator and Auctionator.API and Auctionator.API.v1) ~= nil end

-- Prix minimum à l'HdV (notre scan, sinon Auctionator).
function Prices.AH(id)
    local e = ns.db.market.prices[id] or session[id]
    if e then return e.p end
    return Auctionator_(id)
end

function Prices.Quantity(id)
    local e = ns.db.market.prices[id] or session[id]
    return e and e.q
end

function Prices.History(id) return ns.db.market.hist[id] or {} end

function Prices.VendorBuy(id) return ns.db.vendor[id] or VENDOR_SEED[id] end

-- Prix de revente au marchand ; négatif dans la base de butin = lié quand ramassé.
function Prices.VendorSell(id)
    local v = ns.LootData and ns.LootData.V[id]
    if v then return math.abs(v), v < 0 end
    return select(11, C_Item.GetItemInfo(id)) or 0, false
end

-- Coût d'achat d'un composant : le moins cher entre marchand et HdV.
function Prices.Buy(id)
    local vendor, ah = Prices.VendorBuy(id), Prices.AH(id)
    if vendor and ah then return math.min(vendor, ah) end
    return vendor or ah
end

-- Ce que rapporte une vente à l'HdV (après commission).
function Prices.Sell(id)
    local p = Prices.AH(id)
    return p and p * (1 - AH_CUT)
end

-- Valeur d'un objet ramassé : max(vente HdV, revente marchand) ; lié quand ramassé → marchand.
function Prices.ItemValue(id)
    local hit = valueCache[id]
    if hit then return hit[1], hit[2] end
    local vendor, bound = Prices.VendorSell(id)
    local value, source = vendor, "marchand"
    if not bound then
        local ah = Prices.Sell(id)
        if ah and ah > vendor then value, source = ah, "HdV" end
    end
    valueCache[id] = { value, source }
    return value, source
end

-- Prix marchands vus en jeu (achat).
ns.On("MERCHANT_SHOW", function()
    C_Timer.After(0.3, function()
        for i = 1, GetMerchantNumItems() do
            local info = C_MerchantFrame.GetItemInfo(i)
            local link = GetMerchantItemLink(i)
            local id = link and tonumber(link:match("item:(%d+)"))
            if id and info and not info.hasExtendedCost and (info.price or 0) > 0 then
                ns.db.vendor[id] = info.price / math.max(info.stackCount or 1, 1)
                if ns.Craft then ns.Craft.RecordPattern(id, "SetMerchantItem", i) end
            end
        end
    end)
end)
