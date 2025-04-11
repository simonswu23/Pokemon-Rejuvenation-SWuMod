class Battle_Side
  attr_accessor :effects

  def initialize
    @effects = {}
    #turn durations
    @effects[:LightScreen] = 0
    @effects[:Reflect]     = 0
    @effects[:AuroraVeil]  = 0
    @effects[:AreniteWall] = 0
    @effects[:LuckyChant]  = 0
    @effects[:Mist]        = 0
    @effects[:Safeguard]   = 0
    @effects[:Tailwind]    = 0
    #is either active or it's not
    @effects[:WideGuard]   = false
    @effects[:QuickGuard]  = false
    @effects[:CraftyShield]= false 
    @effects[:MatBlock]    = false
    @effects[:Retaliate]   = false
    @effects[:StickyWeb]   = false
    @effects[:StealthRock] = false
    @effects[:Volcalith] = false
    @effects[:Steelsurge] = false
    @effects[:InvRock] = false
    #has stages of activation
    @effects[:Spikes]      = 0
    @effects[:ToxicSpikes] = 0
    # Gen 9 Mod - Last Respects count
    @effects[:LastRespects] = 0
    # Kaizomod effects
    @effects[:EmbargoSide]     = 0
    @effects[:Wildfire]        = 0
    @effects[:LuckyWind]       = 0
  end

  def screenActive?(type=nil)
    return true if @effects[:AuroraVeil] > 0
    return @effects[:LightScreen] > 0 || @effects[:Reflect] > 0 if type.nil?
    return @effects[:LightScreen] > 0 if type == :special
    return @effects[:Reflect] > 0 if type == :physical
  end

  def protectActive?
    return @effects[:WideGuard] || @effects[:QuickGuard] || @effects[:CraftyShield] || @effects[:MatBlock]
  end 

  def resetProtect
    @effects[:WideGuard]   = false
    @effects[:QuickGuard]  = false
    @effects[:CraftyShield]= false 
    @effects[:MatBlock]    = false
  end 
end

class Battle_Global
  attr_accessor :effects
  def initialize
    #Global effects
    @effects = {}
    #turn durations
    @effects[:GRASSY]             = 0 
    @effects[:MISTY]              = 0 
    @effects[:ELECTERRAIN]        = 0
    @effects[:PSYTERRAIN]         = 0
    @effects[:RAINBOW]            = 0
    #@effects[:Splintered]         = 0 
    @effects[:Gravity]            = 0
    @effects[:MagicRoom]          = 0
    @effects[:FairyLock]          = 0
    @effects[:IonDeluge]          = false
    @effects[:WonderRoom]         = 0
    @effects[:MudSport]           = 0
    @effects[:WaterSport]         = 0
    @effects[:sosBuffer]          = 0
    #either active or isn't
    @effects[:HeavyRain]          = false
    @effects[:HarshSunlight]      = false
    @effects[:Round]              = false
  end
end

class Battle_Party #other data pertaining to specific parties
  attr_accessor :megaEvo
  attr_accessor :uBurst
  attr_accessor :zMove
  attr_accessor :gigaEvo
  def initialize
    #indices for the mon that mega'd, z'd, burst'd, etc
    @megaEvolution  = -1
    @ultraBurst     = -1
    @zMove          = -1
    @gigaEvolution  = -1
  end
end