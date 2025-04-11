class PokeBattle_Battler
  # Streamlining of Minior
  def pbShieldsUp?
    return false if @species != :MINIOR
    return false if @ability != :SHIELDSDOWN || @effects[:Transform]
    return false if self.form != 7

    return true
  end
  # End of Minior streamlining

  def pbCanStatus?(showMessages, ignorestatus = false, moldbroken = self.moldbroken, ownStatus = false) # catchall true/false for situations where one can't be statused
    failure = :none
    failure = :FLOWERVEIL if ((@ability == :FLOWERVEIL || pbPartner.ability == :FLOWERVEIL) && (hasType?(:GRASS) || @battle.FE == :BEWITCHED)) && !moldbroken
    failure = :MISTY if (@battle.FE == :MISTY || @battle.state.effects[:MISTY] > 0) && !isAirborne? # Misty Field
    failure = :AMULETCOIN if Rejuv && @battle.FE == :DRAGONSDEN && hasWorkingItem(:AMULETCOIN) # Dragon's Den
    failure = :STATUSED if (!ignorestatus && !self.status.nil?) || (self.ability == :COMATOSE && @battle.FE != :ELECTERRAIN)
    failure = :Substitute if (@damagestate.substitute || @effects[:Substitute] > 0) && (!@battle.lastMoveUsed.is_a?(Symbol) || !$cache.moves[@battle.lastMoveUsed].checkFlag?(:soundmove)) && !ownStatus
    failure = :SHIELD if pbShieldsUp?
    failure = :Safeguard if pbOwnSide.effects[:Safeguard] > 0 && @battle.battlers[@battle.lastMoveUser].ability != :INFILTRATOR
    if (self.ability == :LEAFGUARD && ((@battle.pbWeather == :SUNNYDAY && !hasWorkingItem(:UTILITYUMBRELLA)) ||
      @battle.FE == :FOREST || @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN, 2, 5) || (Rejuv && @battle.FE == :GRASSY) || @battle.state.effects[:GRASSY] > 0)) && !moldbroken
      failure = :LEAFGUARD
    end
    # Gen 9 Mod - Added Purifying Salt
    failure = :PURIFYINGSALT if self.ability == :PURIFYINGSALT && !moldbroken
    return true if failure == :none
    if showMessages
      case failure
        when :FLOWERVEIL then @battle.pbDisplay(_INTL("{1} is protected by Flower Veil!", pbThis))
        when :MISTY then @battle.pbDisplay(_INTL("Misty Terrain prevents {1} from being inflicted by status!", pbThis(true)))
        when :AMULETCOIN then @battle.pbDisplay(_INTL("Amulet Coin prevents {1} from being inflicted by status on Dragon's Den!", pbThis))
        when :LEAFGUARD then @battle.pbDisplay(_INTL("{1} is protected by Leaf Guard!", pbThis))
        when :STATUSED then @battle.pbDisplay(_INTL("{1} is already statused!", pbThis))
        when :Substitute then @battle.pbDisplay(_INTL("{1} is hiding behind a Substitute!", pbThis))
        when :SHIELD then @battle.pbDisplay(_INTL("{1} shielded itself from status!", pbThis))
        when :Safeguard then @battle.pbDisplay(_INTL("{1}'s team is protected by Safeguard!", pbThis))
        # Gen 9 Mod - Added Purifying Salt
        when :PURIFYINGSALT then @battle.pbDisplay(_INTL("{1} is protected by its Purifying Salt!", pbThis))
      end
    end
    return false
  end

  #===============================================================================
  # Sleep
  #===============================================================================
  def pbCanSleep?(showMessages, selfsleep = false, ignorestatus = false, moldbroken = self.moldbroken)
    return false if isFainted? && !(Rejuv && isbossmon && @shieldCount > 0)
    if (!ignorestatus && status == :SLEEP) || (self.ability == :COMATOSE && @battle.FE != :ELECTERRAIN)
      @battle.pbDisplay(_INTL("{1} is already asleep!", pbThis)) if showMessages
      return false
    end
    return false if !pbCanStatus?(showMessages, ignorestatus, moldbroken, selfsleep)

    failure = :none
    failure = :ABILITY if [:VITALSPIRIT, :INSOMNIA, :SWEETVEIL].include?(self.ability) && !moldbroken
    failure = :SWEETVEIL if pbPartner.ability == :SWEETVEIL && !moldbroken
    failure = :NIGHTMARES if self.ability == :WORLDOFNIGHTMARES
    failure = :ELECTERRAIN if @battle.FE == :ELECTERRAIN && !isAirborne?
    failure = :CONCERT if @battle.ProgressiveFieldCheck(PBFields::CONCERT, 3, 4)
    failure = :EARLYBIRD if self.ability == :EARLYBIRD && !moldbroken && @battle.FE == :SKY
    if self.ability != :SOUNDPROOF
      for i in 0...4
        failure = :Uproar if @battle.battlers[i].effects[:Uproar] > 0
      end
    end
    return true if failure == :none
    if showMessages
      case failure
        when :Uproar then @battle.pbDisplay(_INTL("But the uproar kept {1} awake!", pbThis(true)))
        when :ABILITY then @battle.pbDisplay(_INTL("{1} stayed awake using its {2}!", pbThis, getAbilityName(self.ability)))
        when :SWEETVEIL then @battle.pbDisplay(_INTL("{1} stayed awake using its partner's {2}!", pbThis, getAbilityName(pbPartner.ability)))
        when :NIGHTMARES then @battle.pbDisplay(_INTL("{1}'s dreams jolted them right back up!", pbThis))
        when :ELECTERRAIN then @battle.pbDisplay(_INTL("The electricity jolted {1} awake!", pbThis))
        when :CONCERT then @battle.pbDisplay(_INTL("The concert is too loud and hype to sleep!", pbThis))
        when :EARLYBIRD then @battle.pbDisplay(_INTL("{1} can't fall asleep in the open skies!", pbThis))
      end
    end
    return false
  end

  def pbCanSleepYawn?
    return false if !pbCanStatus?(true)
    if @ability != :SOUNDPROOF
      for i in 0...4
        return false if @battle.battlers[i].effects[:Uproar] > 0
      end
    end
    return false if (@ability == :VITALSPIRIT || @ability == :INSOMNIA) && !self.moldbroken || pbShieldsUp?

    failure = :none
    failure = :SWEETVEIL if (pbPartner.ability == :SWEETVEIL || @ability == :SWEETVEIL) && !self.moldbroken
    failure = :NIGHTMARES if self.ability == :WORLDOFNIGHTMARES
    failure = :ELECTERRAIN if @battle.FE == :ELECTERRAIN && !isAirborne?
    failure = :CONCERT if @battle.ProgressiveFieldCheck(PBFields::CONCERT, 3, 4)
    return true if failure == :none
    case failure
      when :SWEETVEIL then @battle.pbDisplay(_INTL("{1} is protected by Sweet Veil!", pbThis))
      when :NIGHTMARES then @battle.pbDisplay(_INTL("{1}'s dreams jolted them right back up!", pbThis))
      when :ELECTERRAIN then @battle.pbDisplay(_INTL("The electricity jolted {1} awake!", pbThis))
      when :CONCERT then @battle.pbDisplay(_INTL("The concert is too loud and hype to sleep!", pbThis))
    end
    return false
  end

  def pbSleep
    self.status = :SLEEP
    self.statusCount = 2 + @battle.pbRandom(3)
    @battle.pbCommonAnimation("Sleep", self, nil)
  end

  def pbSleepSelf(duration = -1)
    self.status = :SLEEP
    if duration > 0
      self.statusCount = duration
    else
      self.statusCount = 2 + @battle.pbRandom(3)
    end
    @battle.pbCommonAnimation("Sleep", self, nil)
  end

  #===============================================================================
  # Poison
  #===============================================================================
  def pbCanPoison?(showMessages, ownPoison = false, corrosion = false, moldbroken = self.moldbroken)
    return false if isFainted? && !(Rejuv && isbossmon && @shieldCount > 0)

    if status == :POISON
      @battle.pbDisplay(_INTL("{1} is already poisoned.", pbThis)) if showMessages
      return false
    end
    return false if !pbCanStatus?(showMessages, false, moldbroken, ownPoison)
    return true if ownPoison && self.ability == :CORROSION

    failure = :none
    failure = :TYPE if (hasType?(:POISON) || (hasType?(:STEEL) && !hasWorkingItem(:RINGTARGET))) && !(self.corroded || corrosion)
    failure = :ABILITY if self.ability == :IMMUNITY || (self.ability == :PASTELVEIL && @battle.FE != :INFERNAL) && !moldbroken
    failure = :PASTELVEIL if pbPartner.ability == :PASTELVEIL && @battle.FE != :INFERNAL && !moldbroken
    return true if failure == :none
    if showMessages
      case failure
        when :TYPE then @battle.pbDisplay(_INTL("It doesn't affect {1}...", pbThis(true)))
        when :ABILITY then @battle.pbDisplay(_INTL("{1}'s {2} prevents poisoning!", pbThis, getAbilityName(self.ability)))
        when :PASTELVEIL then @battle.pbDisplay(_INTL("{1} stayed healthy using its partner's {2}!", pbThis, getAbilityName(pbPartner.ability)))
      end
    end
    return false
  end

  def pbCanPoisonSynchronize?(opponent, showMessages = false)
    return false if isFainted? && !(Rejuv && isbossmon && @shieldCount > 0)
    return false if !pbCanStatus?(showMessages)

    failure = :none
    failure = :TYPE if (hasType?(:POISON) || (hasType?(:STEEL) && !hasWorkingItem(:RINGTARGET)))
    failure = :ABILITY if self.ability == :IMMUNITY || (self.ability == :PASTELVEIL && @battle.FE != :INFERNAL)
    failure = :PASTELVEIL if pbPartner.ability == :PASTELVEIL && @battle.FE != :INFERNAL
    return true if failure == :none
    case failure
      when :TYPE then @battle.pbDisplay(_INTL("{1}'s {2} had no effect on {3}!", opponent.pbThis, getAbilityName(opponent.ability), pbThis(true)))
      when :ABILITY then @battle.pbDisplay(_INTL("{1}'s {2} prevents {3}'s {4} from working!", pbThis, getAbilityName(self.ability), opponent.pbThis(true), getAbilityName(opponent.ability)))
      when :PASTELVEIL then @battle.pbDisplay(_INTL("{1} stayed healthy using its partner's {2}!", pbThis, getAbilityName(pbPartner.ability)))
    end
    return false
  end

  def pbCanPoisonSpikes?(showMessages = false)
    return false if isFainted? && !(Rejuv && isbossmon && @shieldCount > 0)
    return false if !pbCanStatus?(showMessages)
    return false if hasType?(:POISON) || hasType?(:STEEL)
    return false if self.ability == :IMMUNITY
    return false if (self.ability == :PASTELVEIL && @battle.FE != :INFERNAL)

    if (pbPartner.ability == :PASTELVEIL && @battle.FE != :INFERNAL) && !self.moldbroken
      abilityname = getAbilityName(pbPartner.ability)
      @battle.pbDisplay(_INTL("{1} stayed healthy using its partner's {2}!", pbThis, abilityname)) if showMessages
      return false
    end
    return true
  end

  def pbPoison(attacker, toxic = false)
    self.status = :POISON
    if toxic
      self.statusCount = 1
      self.effects[:Toxic] = 0
    else
      self.statusCount = 0
    end
    if self.index != attacker.index
      @battle.synchronize[0] = self.index
      @battle.synchronize[1] = attacker.index
      @battle.synchronize[2] = :POISON
    end
    @battle.pbCommonAnimation("Poison", self, nil)
  end

  #===============================================================================
  # Burn
  #===============================================================================
  def pbCanBurn?(showMessages, ownFlameOrb = false, moldbroken = self.moldbroken)
    return false if isFainted? && !(Rejuv && isbossmon && @shieldCount > 0)

    if self.status == :BURN
      @battle.pbDisplay(_INTL("{1} already has a burn.", pbThis)) if showMessages
      return false
    end
    return false if !pbCanStatus?(showMessages, false, moldbroken, ownFlameOrb)

    failure = :none
    failure = :WATERBUBBLE if self.ability == :WATERBUBBLE && !moldbroken
    failure = :TYPE if hasType?(:FIRE)
    failure = :WATERVEIL if self.ability == :WATERVEIL && !moldbroken
    failure = :WELLBAKEDBODY if self.ability == :WELLBAKEDBODY && !moldbroken
    failure = :THERMALEXCHANGE if self.ability == :THERMALEXCHANGE && !moldbroken


    return true if failure == :none
    if showMessages
      case failure
        when :WATERBUBBLE then @battle.pbDisplay(_INTL("{1} is protected by its Water Bubble!", pbThis))
        when :TYPE then @battle.pbDisplay(_INTL("It doesn't affect {1}...", pbThis(true)))
        when :WATERVEIL then @battle.pbDisplay(_INTL("{1}'s {2} prevents burns!", pbThis, getAbilityName(self.ability)))
        when :WELLBAKEDBODY then @battle.pbDisplay(_INTL("{1}'s {2} prevents burns!", pbThis, getAbilityName(self.ability)))
        when :THERMALEXCHANGE then @battle.pbDisplay(_INTL("{1}'s {2} prevents burns!", pbThis, getAbilityName(self.ability)))
      end
    end
    return false
  end

  def pbCanBurnSynchronize?(opponent, showMessages = false)
    return false if isFainted? && !(Rejuv && isbossmon && @shieldCount > 0)
    return false if !pbCanStatus?(showMessages)

    failure = :none
    failure = :WATERBUBBLE if self.ability == :WATERBUBBLE && !moldbroken
    failure = :TYPE if hasType?(:FIRE)
    failure = :WATERVEIL if self.ability == :WATERVEIL && !moldbroken
    failure = :WELLBAKEDBODY if self.ability == :WELLBAKEDBODY && !moldbroken
    failure = :THERMALEXCHANGE if self.ability == :THERMALEXCHANGE && !moldbroken
    return true if failure == :none
    case failure
      when :WATERBUBBLE then @battle.pbDisplay(_INTL("{1} is protected by its Water Bubble!", pbThis))
      when :TYPE then @battle.pbDisplay(_INTL("{1}'s {2} had no effect on {3}!", opponent.pbThis, getAbilityName(opponent.ability), pbThis(true)))
      when :WATERVEIL then @battle.pbDisplay(_INTL("{1}'s {2} prevents {3}'s {4} from working!", pbThis, getAbilityName(self.ability), opponent.pbThis(true), getAbilityName(opponent.ability)))
      when :WELLBAKEDBODY then @battle.pbDisplay(_INTL("{1}'s {2} prevents burns!", pbThis, getAbilityName(self.ability)))
      when :THERMALEXCHANGE then @battle.pbDisplay(_INTL("{1}'s {2} prevents burns!", pbThis, getAbilityName(self.ability)))
    end
    return false
  end

  def pbBurn(attacker)
    self.status = :BURN
    self.statusCount = 0
    if self.index != attacker.index
      @battle.synchronize[0] = self.index
      @battle.synchronize[1] = attacker.index
      @battle.synchronize[2] = :BURN
    end
    @battle.pbCommonAnimation("Burn", self, nil)
  end

  #===============================================================================
  # Paralyze
  #===============================================================================
  def pbCanParalyze?(showMessages, moldbroken = self.moldbroken)
    return false if isFainted? && !(Rejuv && isbossmon && @shieldCount > 0)

    if status == :PARALYSIS
      @battle.pbDisplay(_INTL("{1} is already paralyzed!", pbThis)) if showMessages
      return false
    end
    return false if !pbCanStatus?(showMessages, false, moldbroken)

    failure = :none
    failure = :LIMBER if self.ability == :LIMBER && !moldbroken
    failure = :TYPE if hasType?(:ELECTRIC)

    return true if failure == :none
    if showMessages
      case failure
        when :LIMBER then @battle.pbDisplay(_INTL("{1}'s {2} prevents paralysis!", pbThis, getAbilityName(self.ability)))
        when :TYPE then @battle.pbDisplay(_INTL("But it failed!"))
      end
    end
    return false
  end

  def pbCanParalyzeSynchronize?(opponent, showMessages = false)
    return false if !pbCanStatus?(showMessages)

    failure = :none
    failure = :LIMBER if self.ability == :LIMBER && !moldbroken
    failure = :TYPE if hasType?(:ELECTRIC)

    return true if failure == :none
    case failure
      when :TYPE then @battle.pbDisplay(_INTL("{1}'s {2} had no effect on {3}!", opponent.pbThis, getAbilityName(opponent.ability), pbThis(true)))
      when :WATERVEIL then @battle.pbDisplay(_INTL("{1}'s {2} prevents {3}'s {4} from working!", pbThis, getAbilityName(self.ability), opponent.pbThis(true), getAbilityName(opponent.ability)))
    end
    return false
  end

  def pbParalyze(attacker)
    if (attacker.crested == :PLUSLE)
      self.pbBurn(attacker) if self.pbCanBurn?(true)
      return
    end
    if (attacker.crested == :MINUN)
      self.pbFreeze() if self.pbCanFreeze?(true)
      return
      return
    end
    self.status = :PARALYSIS
    self.statusCount = 0
    if self.index != attacker.index
      @battle.synchronize[0] = self.index
      @battle.synchronize[1] = attacker.index
      @battle.synchronize[2] = :PARALYSIS
    end
    @battle.pbCommonAnimation("Paralysis", self, nil)
  end

  #===============================================================================
  # Petrify
  #===============================================================================
  def pbCanPetrify?(showMessages = true)
    return false if isFainted? && !(Rejuv && isbossmon && @shieldCount > 0)

    if status == :PETRIFIED
      @battle.pbDisplay(_INTL("{1} is already petrified!", pbThis)) if showMessages
      return false
    end
    return false if !pbCanStatus?(showMessages)

    if hasType?(:ROCK)
      @battle.pbDisplay(_INTL("But it failed!")) if showMessages
      return false
    end
    return true
  end

  def pbCanPetrifySynchronize?(opponent)
    return false
  end

  def pbPetrify(attacker)
    self.status = :PETRIFIED
    if self.effects[:Substitute] <= 0
      @battle.scene.pbUnSubstituteSprite(self, self.pbIsOpposing?(1))
    else
      @battle.scene.pbSubstituteSprite(self, self.pbIsOpposing?(1))
    end
    self.statusCount = 0
    if self.index != attacker.index
      @battle.synchronize[0] = self.index
      @battle.synchronize[1] = attacker.index
      @battle.synchronize[2] = :PETRIFIED
    end
  end


  #===============================================================================
  # Freeze
  #===============================================================================
  def pbCanFreeze?(showMessages, moldbroken = self.moldbroken)
    return false if isFainted? && !(Rejuv && isbossmon && @shieldCount > 0)
    return false if !pbCanStatus?(showMessages, false, moldbroken)
    return false if self.hasType?(:ICE)
    return false if @battle.pbWeather == :SUNNYDAY && !hasWorkingItem(:UTILITYUMBRELLA) && !KAIZOMOD
    return false if self.ability == :MAGMAARMOR && !moldbroken && @battle.FE != :FROZENDIMENSION
    return false if @battle.FE == :VOLCANIC || @battle.FE == :BURNING

    return true
  end

  def pbFreeze
    self.status = :FROZEN
    self.statusCount = 0
    @battle.pbCommonAnimation("Frozen", self, nil)
  end

  #===============================================================================
  # Generalised status displays
  #===============================================================================
  def pbContinueStatus(showAnim = true)
    case self.status
      when :SLEEP
        @battle.pbCommonAnimation("Sleep", self, nil)
        @battle.pbDisplay(_INTL("{1} is fast asleep.", pbThis))
      when :POISON
        @battle.pbCommonAnimation("Poison", self, nil)
        @battle.pbDisplay(_INTL("{1} is hurt by poison!", pbThis))
      when :BURN
        @battle.pbCommonAnimation("Burn", self, nil)
        @battle.pbDisplay(_INTL("{1} is hurt by its burn!", pbThis))
      when :PARALYSIS
        @battle.pbCommonAnimation("Paralysis", self, nil)
        @battle.pbDisplay(_INTL("{1} is paralyzed! It can't move!", pbThis))
      when :FROZEN
        @battle.pbCommonAnimation("Frozen", self, nil)
        message = KAIZOMOD ? "{1} is hurt by frostbite!" : "{1} is frozen solid!"
        @battle.pbDisplay(_INTL(message, pbThis))
    end
    if self.isbossmon
      if self.chargeAttack
        statusList = KAIZOMOD ? [:SLEEP, :PARALYSIS] : [:SLEEP, :PARALYSIS, :FROZEN]
        if statusList.include?(self.status)
          self.chargeAttack[:turns] += 1
          self.chargeAttack[:canIntermediateAttack] = false
        end
      end
    end
  end

  def pbCureStatus(showMessages = true)
    oldstatus = self.status
    if self.status == :SLEEP
      self.effects[:Nightmare] = false
    end
    self.status = nil
    self.statusCount = 0
    if showMessages
      case oldstatus
        when :SLEEP
          @battle.pbDisplay(_INTL("{1} woke up!", pbThis))
          if self.isbossmon
            if self.chargeAttack
              self.chargeAttack[:canIntermediateAttack] = true
            end
          end
        when :POISON
        when :BURN
        when :PARALYSIS
        when :FROZEN
          return if KAIZOMOD
          @battle.pbDisplay(_INTL("{1} was defrosted!", pbThis))
          if self.isbossmon
            if self.chargeAttack
              self.chargeAttack[:canIntermediateAttack] = true
            end
          end
      end
    end
  end

  #===============================================================================
  # Confuse
  #===============================================================================
  def pbCanConfuse?(showMessages = true, inflictor: nil)
    return false if isFainted? && !(Rejuv && isbossmon && @shieldCount > 0)

    if damagestate.substitute || (@effects[:Substitute] > 0 && !(@battle.lastMoveUsed.is_a?(Symbol) && $cache.moves[@battle.lastMoveUsed].checkFlag?(:soundmove)))
      @battle.pbDisplay(_INTL("But it failed!")) if showMessages
      return false
    end
    if pbOwnSide.effects[:Safeguard] > 0 && (inflictor.nil? || inflictor.ability != :INFILTRATOR)
      @battle.pbDisplay(_INTL("{1}'s team is protected by Safeguard!", pbThis)) if showMessages
      return false
    end
    if !pbCanConfuseSelf?(showMessages, true)
      return false
    end
    return true
  end

  def pbCanConfuseSelf?(showMessages, moldbreakercheck = false)
    return false if isFainted?

    failure = :none
    failure = :Confusion if @effects[:Confusion] > 0
    failure = :OWNTEMPO if self.ability == :OWNTEMPO && !(self.moldbroken && moldbreakercheck)
    failure = :ASHENBEACH if @battle.FE == :ASHENBEACH && (hasType?(:FIGHTING) || self.ability == :INNERFOCUS)
    failure = :MISTY if @battle.FE == :MISTY && !isAirborne? # Misty Field
    return true if failure == :none
    if showMessages
      case failure
        when :Confusion then @battle.pbDisplay(_INTL("{1} is already confused!", pbThis))
        when :OWNTEMPO then @battle.pbDisplay(_INTL("{1}'s {2} prevents confusion!", pbThis, getAbilityName(self.ability)))
        when :ASHENBEACH then @battle.pbDisplay(_INTL("{1} broke through the confusion!", pbThis))
        when :MISTY then @battle.pbDisplay(_INTL("Misty Terrain prevents {1} from being inflicted by status!", pbThis(true)))
      end
    end
    return false
  end

  def pbConfuseSelf
    if @effects[:Confusion] == 0 && self.ability != :OWNTEMPO
      @effects[:Confusion] = 2 + @battle.pbRandom(4)
      @battle.pbCommonAnimation("Confusion", self, nil)
      @battle.pbDisplay(_INTL("{1} became confused!", pbThis))
    end
  end

  def pbContinueConfusion
    @battle.pbCommonAnimation("Confusion", self, nil)
    @battle.pbDisplayBrief(_INTL("{1} is confused!", pbThis))
  end

  def pbCureConfusion(showMessages = true)
    @effects[:Confusion] = 0
    @battle.pbDisplay(_INTL("{1} snapped out of confusion!", pbThis)) if showMessages
  end

  #===============================================================================
  # Attraction
  #===============================================================================
  def pbCanAttract?(attacker, showMessages = true)
    return false if isFainted? && !(Rejuv && isbossmon && @shieldCount > 0)
    return false if !attacker

    if @effects[:Attract] >= 0
      @battle.pbDisplay(_INTL("But it failed!")) if showMessages
      return false
    end
    agender = attacker.gender
    ogender = self.gender
    if (agender == 2 || ogender == 2 || agender == ogender) && !KAIZOMOD
      @battle.pbDisplay(_INTL("But it failed!")) if showMessages
      return false
    end
    if ability == :OBLIVIOUS && !self.moldbroken
      @battle.pbDisplay(_INTL("{1}'s {2} prevents infatuation!", pbThis, getAbilityName(self.ability))) if showMessages
      return false
    end
    return true
  end

  def pbAnnounceAttract(seducer)
    @battle.pbCommonAnimation("Attract", self, nil)
    @battle.pbDisplayBrief(_INTL("{1} is in love with {2}!", pbThis, seducer.pbThis(true)))
  end

  def pbContinueAttract
    @battle.pbDisplay(_INTL("{1} is immobilized by love!", pbThis))
  end

  #===============================================================================
  # Increase stat stages
  #===============================================================================
  def pbTooHigh?(stat, ignoreContrary: false)
    if self.ability == :CONTRARY && !self.moldbroken && !ignoreContrary
      return pbTooLow?(stat, ignoreContrary: true)
    end

    return @stages[stat] >= 6
  end

  def pbCanIncreaseStatStage?(stat, showMessages = false, ignoreContrary: false)
    return false if isFainted? && !(Rejuv && isbossmon && @shieldCount > 0)

    if self.ability == :CONTRARY && !self.moldbroken && !ignoreContrary
      return pbCanReduceStatStage?(stat, showMessages, ignoreContrary: true)
    end

    if pbTooHigh?(stat, ignoreContrary: ignoreContrary)
      @battle.pbDisplay(_INTL("{1}'s {2} won't go any higher!", pbThis, pbGetStatName(stat))) if showMessages
      return false
    end
    return true
  end

  # Gen 9 Mod - Changed definition of pbIncreaseStatBasic to include new 'mirrorable' param, which is required for Opportunist and Mirror Herb.
  def pbIncreaseStatBasic(stat, increment, mirrorable:true)
    increment *= 2 if (self.ability == :SIMPLE) && !(self.moldbroken)
    initial = @stages[stat]
    @stages[stat] += increment
    @stages[stat] = 6 if @stages[stat] > 6
    @effects[:Jealousy] = true
    @statsRaisedSinceLastCheck[stat] += @stages[stat] - initial if mirrorable
  end

  # Gen 9 Mod - Changed definition of pbIncreaseStat to include new 'mirrorable' param, which is required for Opportunist and Mirror Herb.
  # changed from: def pbIncreaseStat(stat,increment,showMessages,attacker=nil,upanim=true)
  def pbIncreaseStat(stat, increment, abilitymessage:true, statmessage:true, ignoreContrary: false, statsource: nil, mirrorable:true)
    # Contrary handling
    if self.ability == :CONTRARY && !self.moldbroken && !ignoreContrary
      @statrepeat = true
      return pbReduceStat(stat, increment, abilitymessage: abilitymessage, statmessage: statmessage, ignoreContrary: true, statdropper: statsource, mirrorable: mirrorable)
    end

    # Increase stat only if you can
    if pbCanIncreaseStatStage?(stat, abilitymessage)
      pbIncreaseStatBasic(stat, increment, mirrorable: mirrorable)

      # Animation
      if !@statupanimplayed
        @battle.pbCommonAnimation("StatUp", self, nil)
        @statupanimplayed = true
      end

      # Battle message
      arrStatTexts = [
        _INTL("{1}'s {2} rose!", pbThis, pbGetStatName(stat)),
        _INTL("{1}'s {2} rose sharply!", pbThis, pbGetStatName(stat)),
        _INTL("{1}'s {2} rose drastically!", pbThis, pbGetStatName(stat)),
        _INTL("{1}'s {2} went way up!", pbThis, pbGetStatName(stat))
      ]
      increment *= 2 if self.ability == :SIMPLE && !self.moldbroken
      if increment > 3
        @battle.pbDisplay(arrStatTexts[3]) if statmessage
      elsif increment == 3
        @battle.pbDisplay(arrStatTexts[2]) if statmessage
      elsif increment == 2
        @battle.pbDisplay(arrStatTexts[1]) if statmessage
      else
        @battle.pbDisplay(arrStatTexts[0]) if statmessage
      end
      @battle.reduceField if stat == PBStats::EVASION && @battle.ProgressiveFieldCheck(PBFields::CONCERT, 2, 4)
      return true
    end
    return false
  end

  #===============================================================================
  # Decrease stat stages
  #===============================================================================
  def pbTooLow?(stat, ignoreContrary: false)
    return @stages[stat] <= -1 if self.ability == :EXECUTION && (stat == PBStats::ATTACK || stat == PBStats::SPATK)

    if self.ability == :CONTRARY && !self.moldbroken && !ignoreContrary
      return pbTooHigh?(stat, ignoreContrary: true)
    end

    return @stages[stat] <= -6
  end

  # Tickle (04A) and Memento (0E2) can't use this, but replicate it instead.
  # (Reason is they lower more than 1 stat independently, and therefore could
  # show certain messages twice which is undesirable.)
  def pbCanReduceStatStage?(stat, showMessages = false, selfreduce = false, ignoreContrary: false)
    return false if isFainted? && !(Rejuv && isbossmon && @shieldCount > 0)

    if self.ability == :CONTRARY && !self.moldbroken && !ignoreContrary
      return pbCanIncreaseStatStage?(stat, showMessages, ignoreContrary: true)
    end

    if !selfreduce
      abilityname = getAbilityName(self.ability) if self.ability
      if damagestate.substitute || @effects[:Substitute] > 0 && !(@battle.lastMoveUsed.is_a?(Symbol) && $cache.moves[@battle.lastMoveUsed].checkFlag?(:soundmove)) && @battle.lastMoveUsed != :PLAYNICE
        @battle.pbDisplay(_INTL("But it failed!")) if showMessages
        return false
      end
      if pbOwnSide.effects[:Mist] > 0 && @battle.battlers[@battle.lastMoveUser].ability != :INFILTRATOR
        @battle.pbDisplay(_INTL("{1} is protected by Mist!", pbThis)) if showMessages
        return false
      end
      if ((self.ability == :CLEARBODY || self.ability == :WHITESMOKE) && !self.moldbroken) || self.ability == :FULLMETALBODY
        @battle.pbDisplay(_INTL("{1}'s {2} prevents stat loss!", pbThis, abilityname)) if showMessages
        return false
      end
      # Gen 9 Mod - Clear Amulet prevents stat loss.
      if hasWorkingItem(:CLEARAMULET)
        itemname = getItemName(self.item) if self.item
        @battle.pbDisplay(_INTL("{1}'s {2} prevents stat loss!", pbThis, itemname)) if showMessages
        return false
      end
      if stat == PBStats::ATTACK && self.ability == :HYPERCUTTER && !self.moldbroken
        @battle.pbDisplay(_INTL("{1}'s {2} prevents Attack loss!", pbThis, abilityname)) if showMessages
        return false
      end
      if stat == PBStats::DEFENSE && self.ability == :BIGPECKS && !self.moldbroken
        @battle.pbDisplay(_INTL("{1}'s {2} prevents Defense loss!", pbThis, abilityname)) if showMessages
        return false
      end
      if stat == PBStats::ACCURACY && !self.moldbroken && self.ability == :KEENEYE
        @battle.pbDisplay(_INTL("{1}'s {2} prevents Accuracy loss!", pbThis, abilityname)) if showMessages
        return false
      end
      if ((ability == :FLOWERVEIL || pbPartner.ability == :FLOWERVEIL) && (hasType?(:GRASS) || @battle.FE == :BEWITCHED)) && !self.moldbroken
        @battle.pbDisplay(_INTL("{1} is protected by Flower Veil!", pbThis)) if showMessages
        return false
      end
    end
    if pbTooLow?(stat)
      @battle.pbDisplay(_INTL("{1}'s {2} won't go any lower!", pbThis, pbGetStatName(stat))) if showMessages
      return false
    end
    return true
  end

  def pbReduceStatBasic(stat, increment)
    increment *= 2 if self.ability == :SIMPLE && !self.moldbroken
    @stages[stat] -= increment
    @stages[stat] = -6 if @stages[stat] < -6
    @statLowered = true
    @effects[:LashOut] = true
  end

  # Gen 9 Mod - Changed definition of pbReduceStat to include new 'mirrorable' param, which is required for Opportunist and Mirror Herb.
  def pbReduceStat(stat,increment,abilitymessage:true,statmessage:true, statdropper: nil, defiant_proc: true, mirrordrop: false, ignoreContrary: false, mirrorable: true)
    # here we play uno reverse if we have Mirror Armor
    if self.ability == :MIRRORARMOR && !mirrordrop && !self.moldbroken && statdropper != self
      if !statdropper.nil?
        if statdropper.hp != 0
          @battle.pbDisplay(_INTL("{1}'s Mirror Armor reflected the stat drop!", pbThis))
          return statdropper.pbReduceStat(stat, increment, abilitymessage: abilitymessage, statmessage: statmessage, mirrordrop: true)
        end
      else
        mirrorOpp = self.pbOppositeOpposing
        if mirrorOpp.hp != 0
          @battle.pbDisplay(_INTL("{1}'s Mirror Armor reflected the stat drop!", pbThis))
          return mirrorOpp.pbReduceStat(stat, increment, abilitymessage: abilitymessage, statmessage: statmessage, mirrordrop: true)
        elsif mirrorOpp.pbPartner.hp != 0
          @battle.pbDisplay(_INTL("{1}'s Mirror Armor reflected the stat drop!", pbThis))
          return mirrorOpp.pbPartner.pbReduceStat(stat, increment, abilitymessage: abilitymessage, statmessage: statmessage, mirrordrop: true)
        end
      end
      @battle.pbDisplay(_INTL("{1}'s Mirror Armor blocked the stat drop!", pbThis))
      return false
    end

    # here we call increase if we have contrary
    if self.ability == :CONTRARY && !ignoreContrary && !self.moldbroken
      return pbIncreaseStat(stat, increment, abilitymessage: abilitymessage, statmessage: statmessage, ignoreContrary: true)
    end

    # Reduce only if you actually can
    if pbCanReduceStatStage?(stat, abilitymessage, statdropper == self)
      pbReduceStatBasic(stat, increment)

      # Reduce animation
      if !@statdownanimplayed
        @battle.pbCommonAnimation("StatDown", self)
        @statdownanimplayed = true
      end

      # Battle message
      increment *= 2 if self.ability == :SIMPLE && !self.moldbroken
      harsh = ""
      harsh = "harshly " if increment == 2
      harsh = "dramatically " if increment >= 3
      stat_text = _INTL("{1}'s {2} {3}fell!", pbThis, pbGetStatName(stat), harsh)
      @battle.pbDisplay(stat_text) if statmessage

      # Defiant/Competitive boost
      if defiant_proc
        if self.ability == :DEFIANT && pbCanIncreaseStatStage?(PBStats::ATTACK) && (statdropper.nil? || self.pbIsOpposing?(statdropper.index))
          increment = 2
          increment = 3 if @battle.FE == :BACKALLEY
          pbIncreaseStat(PBStats::ATTACK, increment, statmessage: false)
          if @battle.FE == :BACKALLEY
            @battle.pbDisplay(_INTL("Defiant dramatically raised {1}'s Attack!", pbThis))
          else
            @battle.pbDisplay(_INTL("Defiant sharply raised {1}'s Attack!", pbThis))
          end
          if @battle.FE == :COLOSSEUM
            pbIncreaseStat(PBStats::DEFENSE, 2, statmessage: false)
            @battle.pbDisplay(_INTL("Defiant sharply raised {1}'s Defense!", pbThis))
          end
        end
        if self.ability == :COMPETITIVE && !(Rejuv && @battle.FE == :CHESS) && pbCanIncreaseStatStage?(PBStats::SPATK) && (statdropper.nil? || self.pbIsOpposing?(statdropper.index))
          increment = 2
          increment = 3 if @battle.FE == :CITY
          pbIncreaseStat(PBStats::SPATK, increment, statmessage: false)
          if @battle.FE == :CITY
            @battle.pbDisplay(_INTL("Competitive dramatically raised {1}'s Special Attack!", pbThis))
          else
            @battle.pbDisplay(_INTL("Competitive sharply raised {1}'s Special Attack!", pbThis))
          end
          if @battle.FE == :COLOSSEUM
            pbIncreaseStat(PBStats::SPDEF, 2, statmessage: false)
            @battle.pbDisplay(_INTL("Defiant sharply raised {1}'s Special Defense!", pbThis))
          end
        end
      end
      @battle.reduceField if (stat == PBStats::EVASION || stat == PBStats::ACCURACY) && @battle.ProgressiveFieldCheck(PBFields::CONCERT, 2, 4)
      return true
    end
    return false
  end

  def pbReduceAttackStatStageIntimidate(opponent)
    # Ways intimidate doesn't work
    return false if isFainted? && !(Rejuv && isbossmon && @shieldCount > 0)
    return false if @effects[:Substitute] > 0

    if [:CLEARBODY, :WHITESMOKE, :HYPERCUTTER, :FULLMETALBODY].include?(self.ability) || (Gen > 7 && [:INNERFOCUS, :OBLIVIOUS, :OWNTEMPO, :SCRAPPY].include?(self.ability))
      abilityname = getAbilityName(self.ability)
      oppabilityname = getAbilityName(opponent.ability)
      @battle.pbDisplay(_INTL("{1}'s {2} prevented {3}'s {4} from working!", pbThis, abilityname, opponent.pbThis(true), oppabilityname))
      if hasWorkingItem(:ADRENALINEORB) && pbCanIncreaseStatStage?(PBStats::SPEED, false) && self.stages[PBStats::ATTACK] > -6
        triggerAdrenalineOrb
      end
      return false
    end
    if pbOwnSide.effects[:Mist] > 0
      @battle.pbDisplay(_INTL("{1} is protected by Mist!", pbThis))
      if hasWorkingItem(:ADRENALINEORB) && pbCanIncreaseStatStage?(PBStats::SPEED, false) && self.stages[PBStats::ATTACK] > -6
        triggerAdrenalineOrb
      end
      return false
    end
    # Gen 9 Mod - Clear Amulet prevents stat drop from intimidate
    if hasWorkingItem(:CLEARAMULET)
      itemname = getItemName(self.item)
      oppabilityname = getAbilityName(opponent.ability)
      @battle.pbDisplay(_INTL("{1}'s {2} prevented {3}'s {4} from working!", pbThis, itemname, opponent.pbThis(true), oppabilityname))
      return false
    end
    # Gen 9 Mod - Guard Dog raises attack on Intimidate
    if (self.ability == :GUARDDOG)
      @battle.pbDisplay(_INTL("{1} got angry!",pbThis))
      pbIncreaseStat(PBStats::ATTACK, 1)
      if hasWorkingItem(:ADRENALINEORB) && pbCanIncreaseStatStage?(PBStats::SPEED, false) && self.stages[PBStats::ATTACK] > -6
        triggerAdrenalineOrb
      end
      return false
    end

    # reduce stat only if you can
    if @battle.FE == :CROWD && pbCanReduceStatStage?(PBStats::DEFENSE, false)
      pbReduceStat(PBStats::DEFENSE, 1, statmessage: false, statdropper: opponent, defiant_proc: false)
      oppabilityname = getAbilityName(opponent.ability)
      @battle.pbDisplay(_INTL("{1}'s {2} cuts {3}'s Defense!", opponent.pbThis, oppabilityname, pbThis(true))) if self.ability != :CONTRARY
      @battle.pbDisplay(_INTL("{1}'s {2} boosts {3}'s Defense!", opponent.pbThis, oppabilityname, pbThis(true))) if self.ability == :CONTRARY
      # Defiant/Competitive
      if self.ability == :DEFIANT
        increment = 2
        increment = 3 if @battle.FE == :BACKALLEY
        pbIncreaseStat(PBStats::ATTACK, increment, statmessage: false)
        if @battle.FE == :BACKALLEY
          @battle.pbDisplay(_INTL("Defiant dramatically raised {1}'s Attack!", pbThis))
        else
          @battle.pbDisplay(_INTL("Defiant sharply raised {1}'s Attack!", pbThis))
        end
      end
      if self.ability == :COMPETITIVE && !(Rejuv && @battle.FE == :CHESS)
        increment = 2
        increment = 3 if @battle.FE == :CITY
        pbIncreaseStat(PBStats::SPATK, increment, statmessage: false)
        if @battle.FE == :CITY
          @battle.pbDisplay(_INTL("Competitive dramatically raised {1}'s Special Attack!", pbThis))
        else
          @battle.pbDisplay(_INTL("Competitive sharply raised {1}'s Special Attack!", pbThis))
        end
      end
    end
    if pbReduceStat(PBStats::ATTACK, 1, statmessage: false, statdropper: opponent, defiant_proc: false)
      # Battle message
      oppabilityname = getAbilityName(opponent.ability)
      @battle.pbDisplay(_INTL("{1}'s {2} cuts {3}'s Attack!", opponent.pbThis, oppabilityname, pbThis(true))) if !(self.ability == :CONTRARY)
      @battle.pbDisplay(_INTL("{1}'s {2} boosts {3}'s Attack!", opponent.pbThis, oppabilityname, pbThis(true))) if (self.ability == :CONTRARY)

      if self.ability == :RATTLED && Gen > 7
        pbIncreaseStat(PBStats::SPEED, 1, statmessage: false)
        @battle.pbDisplay(_INTL("{1}'s Rattled raised its Speed!", pbThis))
      end

      # Defiant/Competitive
      if self.ability == :DEFIANT
        increment = 2
        increment = 3 if @battle.FE == :BACKALLEY
        pbIncreaseStat(PBStats::ATTACK, increment, statmessage: false)
        if @battle.FE == :BACKALLEY
          @battle.pbDisplay(_INTL("Defiant dramatically raised {1}'s Attack!", pbThis))
        else
          @battle.pbDisplay(_INTL("Defiant sharply raised {1}'s Attack!", pbThis))
        end
      end
      if self.ability == :COMPETITIVE && !(Rejuv && @battle.FE == :CHESS)
        increment = 2
        increment = 3 if @battle.FE == :CITY
        pbIncreaseStat(PBStats::SPATK, increment, statmessage: false)
        if @battle.FE == :CITY
          @battle.pbDisplay(_INTL("Competitive dramatically raised {1}'s Special Attack!", pbThis))
        else
          @battle.pbDisplay(_INTL("Competitive sharply raised {1}'s Special Attack!", pbThis))
        end
      end

      # Item triggers
      if hasWorkingItem(:ADRENALINEORB) && pbCanIncreaseStatStage?(PBStats::SPEED, false)
        triggerAdrenalineOrb
      end
      if hasWorkingItem(:WHITEHERB)
        reducedstats = false
        for i in 1..7
          if self.stages[i] < 0
            self.stages[i] = 0
            reducedstats = true
          end
        end
        if reducedstats
          itemname = self.item.nil? ? "" : getItemName(self.item)
          @battle.pbDisplay(_INTL("{1}'s {2} restored its status!", pbThis, itemname))
          pbDisposeItem(false)
        end
      end

      return true
    end
    return false
  end

  def pbReduceStatStagePressure(opponent)
    # Ways Pressure doesn't work
    return false if isFainted? && !(Rejuv && isbossmon && @shieldCount > 0)
    return false if @effects[:Substitute] > 0

    if [:CLEARBODY, :WHITESMOKE, :FULLMETALBODY].include?(self.ability) || (Gen > 7 && [:INNERFOCUS, :OBLIVIOUS, :OWNTEMPO, :SCRAPPY].include?(self.ability))
      abilityname = getAbilityName(self.ability)
      oppabilityname = getAbilityName(opponent.ability)
      @battle.pbDisplay(_INTL("{1}'s {2} prevented {3}'s {4} from working!", pbThis, abilityname, opponent.pbThis(true), oppabilityname))
      if hasWorkingItem(:ADRENALINEORB) && pbCanIncreaseStatStage?(PBStats::SPEED, false) && (self.stages[PBStats::DEFENSE] > -6 || self.stages[PBStats::SPDEF] > -6)
        triggerAdrenalineOrb
      end
      return false
    end
    if pbOwnSide.effects[:Mist] > 0
      @battle.pbDisplay(_INTL("{1} is protected by Mist!", pbThis))
      if hasWorkingItem(:ADRENALINEORB) && pbCanIncreaseStatStage?(PBStats::SPEED, false) && (self.stages[PBStats::DEFENSE] > -6 || self.stages[PBStats::SPDEF] > -6)
        triggerAdrenalineOrb
      end
      return false
    end
    # Gen 9 Mod - Clear Amulet prevents stat drop from Intimidate-like abilities
    if hasWorkingItem(:CLEARAMULET)
      itemname = getItemName(self.item)
      oppabilityname = getAbilityName(opponent.ability)
      @battle.pbDisplay(_INTL("{1}'s {2} prevented {3}'s {4} from working!", pbThis, itemname, opponent.pbThis(true), oppabilityname))
      return false
    end
    # Gen 9 Mod - Guard Dog raises attack on Intimidate-like abilities
    if (self.ability == :GUARDDOG)
      @battle.pbDisplay(_INTL("{1} got angry!",pbThis))
      pbIncreaseStat(PBStats::ATTACK, 1)
      if hasWorkingItem(:ADRENALINEORB) && pbCanIncreaseStatStage?(PBStats::SPEED, false) && (self.stages[PBStats::DEFENSE] > -6 || self.stages[PBStats::SPDEF] > -6)
        triggerAdrenalineOrb
      end
      return false
    end

    spdef_success = pbReduceStat(PBStats::SPDEF, 1, statmessage: false, statdropper: opponent, defiant_proc: false)
    def_success = pbReduceStat(PBStats::DEFENSE, 1, statmessage: false, statdropper: opponent, defiant_proc: false)
    if spdef_success || def_success
      # Battle message
      oppabilityname = getAbilityName(opponent.ability)
      if spdef_success
        if self.ability == :CONTRARY
          @battle.pbDisplay(_INTL("{1}'s {2} boosts {3}'s Special Defense!", opponent.pbThis, oppabilityname, pbThis(true)))
        else
          @battle.pbDisplay(_INTL("{1}'s {2} cuts {3}'s Special Defense!", opponent.pbThis, oppabilityname, pbThis(true)))
        end
      end
      if def_success
        if self.ability == :CONTRARY
          @battle.pbDisplay(_INTL("{1}'s {2} boosts {3}'s Defense!", opponent.pbThis, oppabilityname, pbThis(true)))
        else
          @battle.pbDisplay(_INTL("{1}'s {2} cuts {3}'s Defense!", opponent.pbThis, oppabilityname, pbThis(true)))
        end
      end
      if self.ability == :RATTLED && Gen > 7
        pbIncreaseStat(PBStats::SPEED, 1, statmessage: false)
        @battle.pbDisplay(_INTL("{1}'s Rattled raised its Speed!", pbThis))
      end

      # Defiant/Competitive
      if self.ability == :DEFIANT
        increment = 2
        increment = 3 if @battle.FE == :BACKALLEY
        pbIncreaseStat(PBStats::ATTACK, increment, statmessage: false)
        if @battle.FE == :BACKALLEY
          @battle.pbDisplay(_INTL("Defiant dramatically raised {1}'s Attack!", pbThis))
        else
          @battle.pbDisplay(_INTL("Defiant sharply raised {1}'s Attack!", pbThis))
        end
      end
      if self.ability == :COMPETITIVE && !(Rejuv && @battle.FE == :CHESS)
        increment = 2
        increment = 3 if @battle.FE == :CITY
        pbIncreaseStat(PBStats::SPATK, increment, statmessage: false)
        if @battle.FE == :CITY
          @battle.pbDisplay(_INTL("Competitive dramatically raised {1}'s Special Attack!", pbThis))
        else
          @battle.pbDisplay(_INTL("Competitive sharply raised {1}'s Special Attack!", pbThis))
        end
      end

      # Item triggers
      if hasWorkingItem(:ADRENALINEORB) && pbCanIncreaseStatStage?(PBStats::SPEED, false)
        triggerAdrenalineOrb
      end
      if hasWorkingItem(:WHITEHERB)
        reducedstats = false
        for i in 1..7
          if self.stages[i] < 0
            self.stages[i] = 0
            reducedstats = true
          end
        end
        if reducedstats
          itemname = self.item.nil? ? "" : getItemName(self.item)
          @battle.pbDisplay(_INTL("{1}'s {2} restored its status!", pbThis, itemname))
          pbDisposeItem(false)
        end
      end
      return true
    end
    return false
  end

  def pbReduceSpeedStatStageUnnerve(opponent)
    # Ways Unnerve doesn't work
    return false if isFainted? && !(Rejuv && isbossmon && @shieldCount > 0)
    return false if @effects[:Substitute] > 0

    if [:CLEARBODY, :WHITESMOKE, :FULLMETALBODY].include?(self.ability) || (Gen > 7 && [:INNERFOCUS, :OBLIVIOUS, :OWNTEMPO, :SCRAPPY].include?(self.ability))
      abilityname = getAbilityName(self.ability)
      oppabilityname = getAbilityName(opponent.ability)
      @battle.pbDisplay(_INTL("{1}'s {2} prevented {3}'s {4} from working!", pbThis, abilityname, opponent.pbThis(true), oppabilityname))
      if hasWorkingItem(:ADRENALINEORB) && pbCanIncreaseStatStage?(PBStats::SPEED, false) && self.stages[PBStats::SPEED] > -6
        triggerAdrenalineOrb(true)
      end
      return false
    end
    if pbOwnSide.effects[:Mist] > 0
      @battle.pbDisplay(_INTL("{1} is protected by Mist!", pbThis))
      if hasWorkingItem(:ADRENALINEORB) && pbCanIncreaseStatStage?(PBStats::SPEED, false) && self.stages[PBStats::SPEED] > -6
        triggerAdrenalineOrb(true)
      end
      return false
    end
    # Gen 9 Mod - Clear Amulet prevents stat drop from intimidate
    if hasWorkingItem(:CLEARAMULET)
      itemname = getItemName(self.item)
      oppabilityname = getAbilityName(opponent.ability)
      @battle.pbDisplay(_INTL("{1}'s {2} prevented {3}'s {4} from working!", pbThis, itemname, opponent.pbThis(true), oppabilityname))
      return false
    end
    # Gen 9 Mod - Guard Dog raises attack on Intimidate-related abilities
    if (self.ability == :GUARDDOG)
      @battle.pbDisplay(_INTL("{1} got angry!",pbThis))
      pbIncreaseStat(PBStats::ATTACK, 1)
      if hasWorkingItem(:ADRENALINEORB) && pbCanIncreaseStatStage?(PBStats::SPEED, false) && self.stages[PBStats::SPEED] > -6
        triggerAdrenalineOrb(true)
      end
      return false
    end

    if pbReduceStat(PBStats::SPEED, 1, statmessage: false, statdropper: opponent, defiant_proc: false)
      # Battle message
      oppabilityname = getAbilityName(opponent.ability)
      @battle.pbDisplay(_INTL("{1}'s {2} cuts {3}'s Speed!", opponent.pbThis, oppabilityname, pbThis(true))) if !(self.ability == :CONTRARY)
      @battle.pbDisplay(_INTL("{1}'s {2} boosts {3}'s Speed!", opponent.pbThis, oppabilityname, pbThis(true))) if (self.ability == :CONTRARY)

      if self.ability == :RATTLED && Gen > 7
        pbIncreaseStat(PBStats::SPEED, 2, statmessage: false)
        @battle.pbDisplay(_INTL("{1}'s Rattled sharply raised its Speed!", pbThis))
      end

      # Defiant/Competitive
      if self.ability == :DEFIANT
        increment = 2
        increment = 3 if @battle.FE == :BACKALLEY
        pbIncreaseStat(PBStats::ATTACK, increment, statmessage: false)
        if @battle.FE == :BACKALLEY
          @battle.pbDisplay(_INTL("Defiant dramatically raised {1}'s Attack!", pbThis))
        else
          @battle.pbDisplay(_INTL("Defiant sharply raised {1}'s Attack!", pbThis))
        end
      end
      if self.ability == :COMPETITIVE && !(Rejuv && @battle.FE == :CHESS)
        increment = 2
        increment = 3 if @battle.FE == :CITY
        pbIncreaseStat(PBStats::SPATK, increment, statmessage: false)
        if @battle.FE == :CITY
          @battle.pbDisplay(_INTL("Competitive dramatically raised {1}'s Special Attack!", pbThis))
        else
          @battle.pbDisplay(_INTL("Competitive sharply raised {1}'s Special Attack!", pbThis))
        end
      end

      # Item triggers
      if hasWorkingItem(:ADRENALINEORB) && pbCanIncreaseStatStage?(PBStats::SPEED, false)
        triggerAdrenalineOrb
      end
      if hasWorkingItem(:WHITEHERB)
        reducedstats = false
        for i in 1..7
          if self.stages[i] < 0
            self.stages[i] = 0
            reducedstats = true
          end
        end
        if reducedstats
          itemname = self.item.nil? ? "" : getItemName(self.item)
          @battle.pbDisplay(_INTL("{1}'s {2} restored its status!", pbThis, itemname))
          pbDisposeItem(false)
        end
      end
      return true
    end
    return false
  end

  def triggerAdrenalineOrb(unnerve=false)
    if (unnerve)
      pbIncreaseStat(PBStats::SPEED, 2, statmessage: false)
      @battle.pbDisplay(_INTL("{1}'s Adrenaline Orb sharply raised its Speed!", pbThis(true)))
    else
      pbIncreaseStat(PBStats::SPEED, 1, statmessage: false)
      @battle.pbDisplay(_INTL("{1}'s Adrenaline Orb raised its Speed!", pbThis(true)))
    end
    pbDisposeItem(false)
  end

  # Gen 9 Mod - Supersweet Syrup implementation
  def pbReduceEvasionStatStageSyrup(opponent)
    # Can only trigger once per battle
    return false if opponent.supersweetSyrupTriggered && !KAIZOMOD
    # Regadless if it is effective or not, it is only used once, but on both enemies on double battles.
    if @battle.doublebattle && !opponent.pbOpposing1.isFainted? && !opponent.pbOpposing2.isFainted?
      if opponent.supersweetSyrupTriggeredDoubleBattle == true
        opponent.supersweetSyrupTriggered = true
      else
        opponent.supersweetSyrupTriggeredDoubleBattle = true
      end
    else
      opponent.supersweetSyrupTriggered = true
    end
    # Ways Supersweet Syrup doesn't work
    return false if isFainted? && !(Rejuv && isbossmon && @shieldCount > 0)
    return false if @effects[:Substitute] > 0
    if [:CLEARBODY, :WHITESMOKE, :FULLMETALBODY].include?(self.ability)
      abilityname = getAbilityName(self.ability)
      oppabilityname=getAbilityName(opponent.ability)
      @battle.pbDisplay(_INTL("{1}'s {2} prevented {3}'s {4} from working!", pbThis, abilityname, opponent.pbThis(true), oppabilityname))
      return false
    end
    # Gen 9 Mod - Clear Amulet prevents stat drop
    if hasWorkingItem(:CLEARAMULET)
      itemname=getItemName(self.item)
      oppabilityname=getAbilityName(opponent.ability)
      @battle.pbDisplay(_INTL("{1}'s {2} prevented {3}'s {4} from working!", pbThis, itemname, opponent.pbThis(true), oppabilityname))
      return false
    end
    if pbOwnSide.effects[:Mist] > 0
      @battle.pbDisplay(_INTL("{1} is protected by Mist!",pbThis))
      return false
    end
    # reduce stat only if you can
    inc = KAIZOMOD ? 2 : 1
    if pbReduceStat(PBStats::EVASION, inc, statmessage:false, statdropper: opponent, defiant_proc: false)
      # Battle message
      oppabilityname = getAbilityName(opponent.ability)
      @battle.pbDisplay(_INTL("A supersweet aroma is wafting from the syrup covering {1}! Evasion drops!", opponent.pbThis)) if !(self.ability == :CONTRARY)
      @battle.pbDisplay(_INTL("A supersweet aroma is wafting from the syrup covering {1}! Evasion increases!", opponent.pbThis)) if (self.ability == :CONTRARY)

      # Defiant/Competitive
      if (self.ability == :DEFIANT)
        increment = 2
        increment = 3 if @battle.FE == :BACKALLEY
        pbIncreaseStat(PBStats::ATTACK, increment, statmessage:false)
        if @battle.FE == :BACKALLEY
          @battle.pbDisplay(_INTL("Defiant dramatically raised {1}'s Attack!", pbThis))
        else
          @battle.pbDisplay(_INTL("Defiant sharply raised {1}'s Attack!", pbThis))
        end
      end
      if (self.ability == :COMPETITIVE && !(Rejuv && @battle.FE == :CHESS))
        increment = 2
        increment = 3 if @battle.FE == :CITY
        pbIncreaseStat(PBStats::SPATK, increment, statmessage: false)
        if @battle.FE == :CITY
          @battle.pbDisplay(_INTL("Competitive dramatically raised {1}'s Special Attack!", pbThis))
        else
          @battle.pbDisplay(_INTL("Competitive sharply raised {1}'s Special Attack!", pbThis))
        end
      end

      # Item triggers
      if hasWorkingItem(:WHITEHERB)
        reducedstats = false
        for i in 1..7
        if self.stages[i] < 0
          self.stages[i] = 0; reducedstats = true
          end
        end
        if reducedstats
          itemname = (self.item.nil?) ? "" : getItemName(self.item)
          @battle.pbDisplay(_INTL("{1}'s {2} restored its status!", pbThis, itemname))
          pbDisposeItem(false)
        end
      end

      return true
    end
    return false
  end

  def pbReduceIlluminate(opponent)
    # Ways illuminate doesn't work
    return false if isFainted? && !(Rejuv && isbossmon && @shieldCount > 0)
    return false if @effects[:Substitute] > 0

    if self.ability == :CLEARBODY || self.ability == :WHITESMOKE ||
      self.ability == :FULLMETALBODY || self.ability == :KEENEYE ||
      self.ability == :MINDSEYE # Gen 9 Mod - Added Mind's Eye
      abilityname = getAbilityName(self.ability)
      oppabilityname = getAbilityName(opponent.ability)
      @battle.pbDisplay(_INTL("{1}'s {2} prevented {3}'s {4} from working!", pbThis, abilityname, opponent.pbThis(true), oppabilityname))
      return false
    end
    # Gen 9 Mod - Clear Amulet stops stat drops from Illuminate
    if hasWorkingItem(:CLEARAMULET)
      itemname = getItemName(self.item)
      oppabilityname = getAbilityName(opponent.ability)
      @battle.pbDisplay(_INTL("{1}'s {2} prevented {3}'s {4} from working!", pbThis, itemname, opponent.pbThis(true), oppabilityname))
      return false
    end
    if pbOwnSide.effects[:Mist] > 0
      @battle.pbDisplay(_INTL("{1} is protected by Mist!", pbThis))
      return false
    end

    # reduce stat only if you can
    if pbReduceStat(PBStats::ACCURACY, 1, statmessage: false)
      oppabilityname = getAbilityName(opponent.ability)
      @battle.pbDisplay(_INTL("{1}'s {2} cuts {3}'s Accuracy!", opponent.pbThis, oppabilityname, pbThis(true)))
      return true
    end
    return false
  end

  def pbGetStatName(stat)
    # can't use STATSTRINGS for this bc that doesn't have Acc and Eva
    return ["HP", "Attack", "Defense", "Sp. Attack", "Sp. Defense", "Speed", "Accuracy", "Evasion"][stat]
  end

  # Gen 9 Mod - Method to check for Opportunist and Mirror Herb triggers
  def opportunistCheck
    return if isFainted?
    return if self.ability != :OPPORTUNIST && !hasWorkingItem(:MIRRORHERB)
    for i in @battle.battlers
      next if i.isFainted? || !pbIsOpposing?(i.index)
      hash = i.statsRaisedSinceLastCheck
      if self.ability == :OPPORTUNIST && hash.keys.any? {|stat| hash[stat]>0 && pbCanIncreaseStatStage?(stat)}
        @battle.pbDisplay(_INTL("{1} seized the opportunity to boost its own stats!",pbThis))
        for stat in hash.keys
          pbIncreaseStat(stat,hash[stat], abilitymessage:false, mirrorable:false)
        end
      end
      if hasWorkingItem(:MIRRORHERB) && hash.keys.any? {|stat| hash[stat] > 0 && pbCanIncreaseStatStage?(stat)}
        @battle.pbDisplay(_INTL("{1} used its {2} to mirror its opponent's stat boosts!",pbThis, getItemName(self.item)))
        for stat in hash.keys
          pbIncreaseStat(stat, hash[stat], abilitymessage:false, mirrorable:false)
        end
        pbDisposeItem(false)
      end
    end
  end
end
