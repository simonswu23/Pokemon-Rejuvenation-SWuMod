class AI_MonData
  attr_accessor :index # To help ensure we keep the right data with the right battler
  attr_accessor :roles # This is for roles that belong to the current battler
  attr_accessor :trainer
  attr_accessor :partyroles # This is for roles that belong to the entire party
  attr_accessor :skill
  attr_accessor :party
  attr_accessor :scorearray
  attr_accessor :roughdamagearray
  attr_accessor :itemscore
  attr_accessor :shouldswitchscore
  attr_accessor :switchscore
  attr_accessor :shouldMegaOrUltraBurst
  attr_accessor :zmove
  attr_accessor :attitemworks
  attr_accessor :oppitemworks


  def initialize(trainer, index, battle)
    @trainer = trainer
    @index   = index
    @skill   = trainer.nil? ? 0 : trainer.skill
    @party   = trainer.nil? ? [] : battle.pbPartySingleOwner(index)
    @roles   = []
    # there are four move arrays, but one of them doesn't get used depending on the index of the aimon
    @scorearray = [[-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1]]
    @roughdamagearray = [[-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1]] # again, for doubles...
    @itemscore = {}
    @switchscore = []
    @shouldswitchscore = -10000
    @shouldMegaOrUltraBurst = false
    @zmove = nil
    @attitemworks = true
    @oppitemworks = true
  end
end

class PokeBattle_AI
  attr_accessor :battle # Current battle the AI is pulling from (PokeBattle_Battle)
  attr_accessor :move # Current move being scored (PokeBattle_Move)
  attr_accessor :attacker # User of the current move being scored (PokeBattle_Battler)
  attr_accessor :opponent # Opposing pokemon that the move will be used on (PokeBattle_Battler)
  attr_accessor :aimondata # Array of all trainers in the battle (AI_PokemonData)
  attr_accessor :mondata # Current trainer being processed (AI_PokemonData)
  attr_accessor :miniscore # holder for the miniscore (Number)
  attr_accessor :score     # holder for the score-score (Number)
  attr_accessor :index     # index of the battler being evaluated (Number)
  attr_accessor :aiMoveMemory # Moves the AI knows about (Array of move numbers)
  attr_accessor :initial_scores # scores of all moves for a target (Array of scores)
  attr_accessor :score_index # index of current move being evaluated

  # We can adjust the thresholds as we work on things
  MINIMUMSKILL = 1
  LOWSKILL = 10
  MEDIUMSKILL = 30
  HIGHSKILL = 60
  BESTSKILL = 100

  # Function codes you might want to use on your partner.
  PARTNERFUNCTIONS = [0x40, 0x41, 0x55, 0x63, 0x66, 0x67, 0xA0, 0xC1, 0xDF, 0x142, 0x162, 0x164, 0x167, 0x169, 0x170, 0x11d, 0x185, 0x317, 0x91C, 0x907]
  #Swagger, Flatter, Psych Up, Simple Beam, Entrainment, Skill Swap, Frost Breath, Beat Up,
  #Heal Pulse, Topsy-Turvy, Floral Healing, Instruct, Pollen Puff, Purify, Spotlight, After You
  # Gen 9 Mod - Added Spicy Extract and Dragon Cheer

  ######################################################
  # Core functions
  ######################################################
  # Do what we can to setup at the start of the battle

  def initialize(battle)
    @battle = battle
    @aimondata = [nil, nil, nil, nil]
    @aiMoveMemory = {}
    player = @battle.player
    opponent = @battle.opponent
    if @battle.doublebattle
      if player.is_a?(Array)
        @aimondata[0] = AI_MonData.new(player[0], 0, @battle)
        @aimondata[2] = AI_MonData.new(player[1], 2, @battle)
        @aiMoveMemory[player[0]] = {}
        @aiMoveMemory[player[1]] = {}
      else
        @aimondata[0] = AI_MonData.new(player, 0, @battle)
        @aimondata[2] = AI_MonData.new(player, 2, @battle)
        @aiMoveMemory[player] = {}
      end
      if opponent && opponent.is_a?(Array)
        @aimondata[1] = AI_MonData.new(opponent[0], 1, @battle)
        @aimondata[3] = AI_MonData.new(opponent[1], 3, @battle)
        @aiMoveMemory[opponent[0]] = {}
        @aiMoveMemory[opponent[1]] = {}
      elsif opponent
        @aimondata[1] = AI_MonData.new(opponent, 1, @battle)
        @aimondata[3] = AI_MonData.new(opponent, 3, @battle)
        @aiMoveMemory[opponent] = {}
      else
        @aimondata[1] = AI_MonData.new(nil, 1, @battle)
        @aimondata[3] = AI_MonData.new(nil, 3, @battle)
      end
    else
      @aimondata[0] = AI_MonData.new(player, 0, @battle)
      @aiMoveMemory[player] = {}
      if @battle.opponent
        @aimondata[1] = AI_MonData.new(opponent, 1, @battle)
        @aiMoveMemory[opponent] = {}
      else
        @aimondata[1] = AI_MonData.new(nil, 1, @battle)
      end
    end
    # Having set up the data objects, get their roles (if applicable)
    for data in @aimondata
      next if data.nil?

      @mondata = data
      @mondata.partyroles = @mondata.skill >= HIGHSKILL ? pbGetMonRoles : Array.new(@mondata.party.length) { Array.new() }
    end
    setUpDebugLog
  end

  def setUpDebugLog()
    if @battle.pbIsWild?
      PBDebug.setFileName("")
      return
    end
    timestring = Time.new.strftime("%Y-%m-%d_%H-%M-%S")
    trainame = $PokemonGlobal.partner && @battle.doublebattle ? "#{$Trainer.name} and #{@battle.player[1].fullname}" : $Trainer.name
    trainame = trainame.gsub(/[^0-9A-Za-z ]/, '')
    fieldname = PokeBattle_Field.getFieldName(@battle.FE)
    oppname = @battle.opponent.kind_of?(Array) ? "#{@battle.opponent[0].fullname} and #{@battle.opponent[1].fullname}" : @battle.opponent.fullname
    battleformat = @battle.doublebattle ? "Doubles" : "Singles"
    oppname = oppname.gsub(/[^0-9A-Za-z ]/, '')
    filename = "battlelog - #{timestring} - #{trainame} vs. #{oppname} (#{fieldname} #{battleformat})"
    PBDebug.setFileName(filename)
    PBDebug.log("#{GAMETITLE} #{GAMEVERSION} - #{filename}")
    PBDebug.log("Battle seed: " + @battle.seed.to_s)
  end

  def processAIturn
    # Clear old data
    for index in 0...@aimondata.length
      next if @aimondata[index].nil?
      clearMonDataTurn(@aimondata[index])
    end

    # Get the scores for each mon in battle
    for index in 0...@aimondata.length
      next if @aimondata[index].nil?
      # Skip AI processing for player's pokemon unless the AI is supposed to control the player or this is a double battle with AI partner.
      # When having AI partner the AI also determines what the player might do and then uses that prediction for coordinateActions.
      next if @battle.pbOwnedByPlayer?(index) && !@battle.controlPlayer && !@battle.player.is_a?(Array)
      next if !@battle.pbCanShowCommands?(index) || @battle.battlers[index].hp == 0

      @mondata = @aimondata[index]
      # load up the class variables
      @index = index
      @attacker = pbCloneBattler(@index)
      $ai_log_data[index].reset(@attacker) # AI data collection
      @opponent = @attacker.pbOppositeOpposing
      @mondata.roles = pbGetMonRoles(@attacker)
      # Check for conditions where the attacker object is not the one we want to score
      checkMega()
      checkUltraBurst()
      checkGiga()
      # Actually get the scores
      checkZMoves()
      buildMoveScores()
      # we set @opponent for Itemscore and Switchingscore
      @opponent = firstOpponent()
      getItemScore()
      getSwitchingScore()
    end
    # Coordination if there are two mons on the same side
    if @battle.doublebattle
      coordinateActions(1, 3, 0, 2)
      coordinateActions(0, 2, 1, 3) if @battle.controlPlayer || @battle.player.is_a?(Array)
    end
    # At this point, the processing is done and the AI should register its decisions
    # but i don't know how to do that, and i think we can do it from the battle side anyway
    # so as far as the ai code is concerned, we're done now.
    # We have the scores, now we decide what we want to do with them
    chooseAction()
  end

  def pbCloneBattler(index, illusion = false)
    original = illusion ? @battle.battlers[index].effects[:Illusion] : @battle.battlers[index]
    battler = original.clone
    battler.pokemon = original.pokemon.clone
    battler.form = original.form.clone
    battler.pokemon.hp = original.pokemon.hp.clone
    battler.moves = original.moves.clone
    for i in 0...original.moves.length
      battler.moves[i] = original.moves[i].clone
    end
    battler.stages = original.stages.clone
    for i in 0...original.stages.length
      battler.stages[i] = original.stages[i].clone
    end
    battler.effects = original.effects
    return battler
  end

  def clearMonDataTurn(mondata)
    mondata.shouldMegaOrUltraBurst = false
    mondata.scorearray = [[-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1]]
    mondata.roughdamagearray = [[-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1], [-1, -1, -1, -1]]
    mondata.itemscore = {}
    mondata.switchscore = []
    mondata.shouldswitchscore = -10000
    mondata.zmove = nil
  end

  def checkMega
    return if !@battle.pbCanMegaEvolve?(@index)

    want_to_mega = true
    # Run through conditions to see if you don't want to mega
    return if !want_to_mega

    # and if you want to mega, change the attacker
    @attacker.pokemon.makeMega
    @attacker.form = @attacker.pokemon.form
    @attacker.pbUpdate(true)
    @mondata.shouldMegaOrUltraBurst = true
  end

  def checkUltraBurst
    return if !@battle.pbCanUltraBurst?(@index)

    # change the attacker to be itself but ultra bursted
    @attacker.pokemon.makeUltra
    @attacker.form = @attacker.pokemon.form
    @attacker.pbUpdate(true)
    @mondata.shouldMegaOrUltraBurst = true
  end

  def checkGiga
		return if !@battle.pbCanGigaEvolve?(@index)
		want_to_giga=true
		#Run through conditions to see if you don't want to giga
		return if !want_to_giga
		#and if you want to giga, change the attacker
		@attacker.pokemon.makeGiga
		@attacker.form=@attacker.pokemon.form
		@attacker.pbUpdate(fullchange=true,giga=true)
		@mondata.shouldMegaOrUltraBurst = true
	end

  def checkZMoves
    return if @attacker.zmoves.nil?
    return if !@battle.pbCanZMove?(@index)

    # Special case processing- there are specific moves that should intentionally be made z-moves
    # if both the move and the z-crystal are present
    bestbase = 0
    for i in 0...@attacker.zmoves.length
      move = @attacker.zmoves[i]
      next if move.nil?
      next if @attacker.moves[i].nil?
      next if @attacker.moves[i].pp == 0

      if (move.move == :CONVERSION || move.move == :SPLASH || move.move == :CELEBRATE) && @attacker.item == :NORMALIUMZ
        zmove = move
        break
      end
      if (move.move == :NATUREPOWER && @attacker.item == :NORMALIUMZ)
        newmove = PokeBattle_Move.pbFromPBMove(@battle, PBMove.new(@battle.field.naturePower), @attacker)
        if newmove.basedamage > 0
          zmove = PokeBattle_Move.pbFromPBMove(@battle, PBMove.new(PBStuff::CRYSTALTOZMOVE[PBStuff::TYPETOZCRYSTAL[newmove.type]]), @attacker, newmove)
          break
        end
      end
      if (move.move == :EXTREMEEVOBOOST && @attacker.item == :EEVIUMZ)
        zmove = move
        break
      end
      next if $cache.moves[move.move].category == :status # Skip all other status moves

      thisbase = move.basedamage
      if bestbase < thisbase
        bestbase = thisbase
        zmove = move
      end
    end
    # if there's a zmove, put it on the moves list and run it with the rest
    if zmove
      @attacker.moves.push(zmove)
      @mondata.zmove = zmove
      @mondata.scorearray.each { |array| array.push(-1) }
      @mondata.roughdamagearray.each { |array| array.push(-1) }
    end
  end

  def buildMoveScores
    # this is the framework for getting the move scores. minimal calculation should be done here
    if !@battle.opponent && @battle.pbIsOpposing?(@index) && !(Rejuv && (@battle.battlers[@index].isbossmon || @battle.battlers[@index].issossmon)) # First check if this is a wild battle
      preference = @attacker.personalID % 4
      for j in [0, 2]
        next if j == 2 && !@battle.doublebattle

        for i in 0...4
          if @battle.pbCanChooseMove?(index, i, false)
            @mondata.scorearray[j][i] = 100
            @mondata.scorearray[j][i] += 5 if preference == i # for personality
          end
        end
      end
      return
    end
    # real code time.
    if @battle.doublebattle # this JUST gets the numbers. other things can be computed later.
      for monindex in 0...@battle.battlers.length
        next if monindex == @index # This is you! We don't want to hit ourselves.
        next if @battle.battlers[monindex].isFainted? # Can't hit 'em if they're dead

        @opponent = pbCloneBattler(monindex)
        # Save the amount of damage the AI think opp can do
        $ai_log_data[@index].expected_damage.push((checkAIdamage() * 100.0 / @attacker.totalhp).round(1)) unless monindex == @attacker.pbPartner.index || !$INTERNAL
        $ai_log_data[@index].expected_damage_name.push(getMonName(@opponent.species)) unless monindex == @attacker.pbPartner.index || !$INTERNAL
        # get the moves the pokemon can choose, in case of choice item/encore/taunt/torment
        for moveindex in 0...@attacker.moves.length
          next if !@battle.pbCanChooseMove?(@index, moveindex, false)

          @move = pbChangeMove(@attacker.moves[moveindex], @attacker)
          # if you can't/shouldn't hit your partner with the move, skip it
          next if @attacker.pbPartner.index == monindex && (@attacker.pbTarget(@move) != :AllNonUsers && !PARTNERFUNCTIONS.include?(@move.function))

          if @move.basedamage != 0
            @mondata.roughdamagearray[monindex][moveindex] = [(pbRoughDamage * 100) / (@opponent.hp), 110].min
          # The old function makes some adjustments for two-turn moves here. I'm leaving that for later.
          else
            @mondata.roughdamagearray[monindex][moveindex] = getStatusDamage
          end
        end

        for moveindex in 0...@attacker.moves.length
          next if !@battle.pbCanChooseMove?(@index, moveindex, false)

          @move = pbChangeMove(@attacker.moves[moveindex], @attacker)
          next if @attacker.pbPartner.index == monindex && (@attacker.pbTarget(@move) != :AllNonUsers && !PARTNERFUNCTIONS.include?(@move.function))

          @mondata.scorearray[monindex][moveindex] = getMoveScore(@mondata.roughdamagearray[monindex], moveindex)
          # at this point we have legally acquired the move scores and thus should be done.
        end
        # add z-move if relevant
        if @mondata.zmove && @attacker.pbPartner.index != monindex
          @move = @mondata.zmove
          if @move.basedamage != 0 && @opponent.hp > 0
            @mondata.roughdamagearray[monindex][-1] = [(pbRoughDamage * 100) / (@opponent.hp), 110].min
          else
            @mondata.roughdamagearray[monindex][-1] = getStatusDamage
          end
          @mondata.scorearray[monindex][-1] = getMoveScore(@mondata.roughdamagearray[monindex], @mondata.roughdamagearray[monindex].length - 1)
        end

        # Add struggle
        has_to_struggle = true
        @attacker.moves.each_with_index { |move, moveindex| has_to_struggle = false if @battle.pbCanChooseMove?(@index, moveindex, false) }
        if has_to_struggle
          next if @attacker.pbPartner.index == monindex

          @move = @battle.struggle
          @mondata.roughdamagearray[monindex][0] = [(pbRoughDamage * 100) / (@opponent.hp), 110].min
          @mondata.scorearray[monindex][0] = getMoveScore(@mondata.roughdamagearray[monindex], 0)
        end
      end
    else
      oppindex = @index ^ 1
      @opponent = pbCloneBattler(oppindex, illusionCheck(@attacker, @battle.battlers[oppindex]))
      $ai_log_data[@index].expected_damage.push((checkAIdamage() * 100.0 / @attacker.totalhp).round(1)) if $INTERNAL
      $ai_log_data[@index].expected_damage_name.push(getMonName(@opponent.species)) if $INTERNAL
      # get the moves the pokemon can choose, in case of choice item/encore/taunt/torment
      for moveindex in 0...@attacker.moves.length
        next if !@battle.pbCanChooseMove?(@index, moveindex, false)

        @move = pbChangeMove(@attacker.moves[moveindex], @attacker)
        if @move.basedamage != 0
          @mondata.roughdamagearray[oppindex][moveindex] = [(pbRoughDamage * 100) / (@opponent.hp), 110].min
        # The old function makes some adjustments for two-turn moves here. I'm leaving that for later.
        else
          @mondata.roughdamagearray[oppindex][moveindex] = getStatusDamage
        end
      end
      for moveindex in 0...@attacker.moves.length
        next if !@battle.pbCanChooseMove?(@index, moveindex, false)

        @move = @attacker.moves[moveindex]
        @mondata.scorearray[oppindex][moveindex] = getMoveScore(@mondata.roughdamagearray[oppindex], moveindex)
        # at this point we have legally acquired the move scores and thus should be done.
      end
      # add z-move if relevant
      if @mondata.zmove
        @move = @mondata.zmove
        if @move.basedamage != 0
          @mondata.roughdamagearray[oppindex][-1] = [(pbRoughDamage * 100) / (@opponent.hp), 110].min
        else
          @mondata.roughdamagearray[oppindex][-1] = getStatusDamage
        end
        @mondata.scorearray[oppindex][-1] = getMoveScore(@mondata.roughdamagearray[oppindex], @mondata.scorearray[oppindex].length - 1)
      end

      # Add struggle
      has_to_struggle = true
      @attacker.moves.each_with_index { |move, moveindex| has_to_struggle = false if @battle.pbCanChooseMove?(@index, moveindex, false) }
      if has_to_struggle
        @move = @battle.struggle
        @mondata.roughdamagearray[oppindex][0] = [(pbRoughDamage * 100) / (@opponent.hp), 110].min
        @mondata.scorearray[oppindex][0] = getMoveScore(@mondata.roughdamagearray[oppindex], 0)
      end
    end
  end

  def chooseAction
    for index in 0...@aimondata.length # for every battler
      next if @aimondata[index].nil?
      next if @battle.pbOwnedByPlayer?(index) && !@battle.controlPlayer

      battler = @battle.battlers[index]
      next if battler.hp == 0 || !@battle.pbCanShowCommands?(index)
      next if @battle.choices[battler.index] != [nil]

      @mondata = @aimondata[index]
      # make move-targets coupled list bc that works way easier ?
      @mondata.scorearray.map! { |scorelist| scorelist.map! { |score| score < 0 ? -1 : score } }
      # make list of moves, targets, and scores, # structured [moveindex, [target(s)], score, isZmove?]
      chooseablemoves = findChoosableMoves(battler, @mondata)


      chooseablemoves = chooseablemoves.find_all { |arrays| arrays[:score] >= 0 }
      # dealing with mon that can't even choose fight menu
      if !@battle.pbCanShowCommands?(battler.index)
        @battle.pbAutoChooseMove(battler.index)
        next
      end

      if chooseablemoves.length != 0
        maxmovescore = chooseablemoves.max { |a1, a2| a1[:score] <=> a2[:score] }[:score] rescue 0
      else
        maxmovescore = 0
      end
      # chooses the action that the AI pokemon will perform
      # SWITCH
      if @mondata.shouldswitchscore > maxmovescore && @mondata.switchscore.max > 100 # arbitrary
        if battler.index == 3 && @battle.choices[1][0] == :switch && @battle.choices[1][1] == @mondata.switchscore.index(@mondata.switchscore.max)
          if @mondata.switchscore.max(2)[1] > 100 && shouldHardSwitch?(battler, @mondata.switchscore.index(@mondata.switchscore.max(2)[1]))
            indexhighestscore = @mondata.switchscore.index(@mondata.switchscore.max(2)[1])
            highestscoremon = @battle.pbParty(battler.index)[indexhighestscore]
            PBDebug.log(sprintf("Switching to %s", getMonName(highestscoremon.species))) if $INTERNAL
            $ai_log_data[battler.index].chosen_action = sprintf("Switching to %s", getMonName(highestscoremon.species))
            @battle.pbRegisterSwitch(battler.index, indexhighestscore)
            next
          end
        elsif shouldHardSwitch?(battler, @mondata.switchscore.index(@mondata.switchscore.max))
          indexhighestscore = @mondata.switchscore.index(@mondata.switchscore.max)
          highestscoremon = @battle.pbParty(battler.index)[indexhighestscore]
          PBDebug.log(sprintf("Switching to %s", getMonName(highestscoremon.species))) if $INTERNAL
          $ai_log_data[battler.index].chosen_action = sprintf("Switching to %s", getMonName(highestscoremon.species))
          @battle.pbRegisterSwitch(battler.index, indexhighestscore)
          next
        end
      end

            # USE ITEM
      if !@mondata.itemscore.empty? && @mondata.itemscore.values.max > maxmovescore
        item = @mondata.itemscore.key(@mondata.itemscore.values.max)
        # check if quantity of item the battler has is 1 and if previous battler hasn't also tried to use this item
        if battler.index == 3 && @battle.choices[1][0] == :item && @battle.choices[1][1] == item
          items = @battle.pbGetOwnerItems(battler.index)
          if items.count { |element| element == item } > 1
            @battle.pbRegisterItem(battler.index, item)
            $ai_log_data[battler.index].chosen_action = sprintf("Using Item %s", getItemName(item))
            next
          end
        else
          @battle.pbRegisterItem(battler.index, item)
          $ai_log_data[battler.index].chosen_action = sprintf("Using Item %s", getItemName(item))
          next
        end
      end

      if !@battle.pbCanShowCommands?(battler.index) || (0..3).none? { |number| @battle.pbCanChooseMove?(battler.index, number, false) }
        @battle.pbAutoChooseMove(battler.index)
        next
      end
      # MEGA+BURST
      if @aimondata[index].shouldMegaOrUltraBurst
        @battle.pbRegisterMegaEvolution(index) if @battle.pbCanMegaEvolve?(index)
        @battle.pbRegisterUltraBurst(index) if @battle.pbCanUltraBurst?(index)
        @battle.pbRegisterGigaEvolution(index) if @battle.pbCanGigaEvolve?(index)
      end

      # MOVE
      canusemovelist = []
      for moveindex in 0...battler.moves.length
        canusemovelist.push(moveindex) if @battle.pbCanChooseMove?(battler.index, moveindex, false)
      end
      if chooseablemoves.length == 0 && canusemovelist.length > 0
        @battle.pbRegisterMove(battler.index, canusemovelist[@battle.pbRandom(canusemovelist.length)], false)
        @battle.pbRegisterTarget(battler.index, battler.pbOppositeOpposing.index) if @battle.doublebattle
        $ai_log_data[battler.index].chosen_action = "Random Move bc only bad decisions"
        next
      elsif chooseablemoves.length == 0
        @battle.pbAutoChooseMove(battler.index)
      end
      # Minmax choices depending on AI
      if @mondata.skill >= MEDIUMSKILL
        threshold = @mondata.skill >= BESTSKILL ? 1.5 : @mondata.skill >= HIGHSKILL ? 2 : 3
        newscore = @mondata.skill >= BESTSKILL ? 5 : @mondata.skill >= HIGHSKILL ? 10 : 15
        for scoreindex in 0...chooseablemoves.length
          chooseablemoves[scoreindex][:score] = chooseablemoves[scoreindex][:score] > newscore && chooseablemoves[scoreindex][:score] * threshold < maxmovescore ? newscore : chooseablemoves[scoreindex][:score]
        end
      end

      # Log the move scores in debuglog
      if $INTERNAL
        x = "[#{battler.pbThis}: "
        j = 0
        for i in 0...4
          next if battler.moves[i].nil?

          x += ", " if j > 0
          movelistscore = [@mondata.scorearray[0][i], @mondata.scorearray[1][i], @mondata.scorearray[2][i], @mondata.scorearray[3][i]]
          x += battler.moves[i].name + "=" + movelistscore.to_s
          j += 1
        end
        x += "]"
        PBDebug.log(x)
        $stdout.print(x)
        $stdout.print("\n")
      end

      preferredMoves = []
      for i in chooseablemoves
        if i[:score] >= (maxmovescore * 0.95)
          preferredMoves.push(i)
          preferredMoves.push(i) if i[:score] == maxmovescore # Doubly prefer the best move
        end
      end

      chosen = preferredMoves[@battle.pbRandom(preferredMoves.length)]
      if chosen[:zmove]
        PBDebug.log("[Prefer " + battler.zmoves[chosen[:moveindex]].name + "]") if $INTERNAL
        $ai_log_data[battler.index].chosen_action = "[Prefer " + battler.zmoves[chosen[:moveindex]].name + "]"
      else
        PBDebug.log("[Prefer " + battler.moves[chosen[:moveindex]].name + "]") if $INTERNAL
        $ai_log_data[battler.index].chosen_action = "[Prefer " + battler.moves[chosen[:moveindex]].name + "]"
      end
      @battle.pbRegisterZMove(battler.index) if chosen[:zmove] == true # if chosen move is a z-move
      @battle.pbRegisterMove(battler.index, chosen[:moveindex], false)
      @battle.pbRegisterTarget(battler.index, chosen[:target][0]) if @battle.doublebattle
    end
  end

  def findChoosableMoves(battler, mondata)
    chooseablemoves = []
    for moveindex in 0...4
      next if !@battle.pbCanChooseMove?(battler.index, moveindex, false)

      # Wild pokemon can choose any move and can target either side in doubles.
      if !@battle.opponent && @battle.pbIsOpposing?(battler.index) && !(battler.isbossmon || battler.issossmon)
        chooseablemoves.push({ moveindex: moveindex, target: [@battle.sample([0, 2])], score: mondata.scorearray[0][moveindex], zmove: false })
        next
      end

      move = pbChangeMove(battler.moves[moveindex], battler)
      oi = battler.pbOppositeOpposing.index # opposite opponent
      if @battle.doublebattle
        pi = battler.pbPartner.index # partner
        ci = battler.pbCrossOpposing.index
        case battler.pbTarget(move)
          when :SingleNonUser, :SingleOpposing
            [oi, pi, ci].each do |targetindex|
              chooseablemoves.push({ moveindex: moveindex, target: [targetindex], score: mondata.scorearray[targetindex][moveindex], zmove: false })
            end
          when :RandomOpposing, :User, :NoTarget, :UserSide
            if @battle.battlers[oi].hp > 0 && @battle.battlers[ci].hp > 0
              chooseablemoves.push({ moveindex: moveindex, target: [oi], score: (mondata.scorearray[ci][moveindex] + mondata.scorearray[oi][moveindex]) / 2, zmove: false })
            elsif @battle.battlers[oi].hp > 0
              chooseablemoves.push({ moveindex: moveindex, target: [oi], score: mondata.scorearray[oi][moveindex], zmove: false })
            else
              chooseablemoves.push({ moveindex: moveindex, target: [ci], score: mondata.scorearray[ci][moveindex], zmove: false })
            end
          when :AllOpposing, :OpposingSide
            chooseablemoves.push({ moveindex: moveindex, target: [oi, ci], score: (mondata.scorearray[ci][moveindex] + mondata.scorearray[oi][moveindex]), zmove: false })
          when :AllNonUsers
            scoremult = 1.0
            if mondata.trainer && (mondata.trainer.trainertype == :UMBTITANIA || mondata.trainer.trainertype == :UMBAMARIA) && @battle.doublebattle
              scoremult *= (1 + 2 * mondata.scorearray[pi][moveindex] / 100.0)
            elsif (move.pbType(battler) == :FIRE && (battler.pbPartner.ability == :FLASHFIRE || battler.pbPartner.crested == :DRUDDIGON)) ||
                  (move.pbType(battler) == :WATER && (battler.pbPartner.ability == :WATERABSORB || battler.pbPartner.ability == :STORMDRAIN || battler.pbPartner.ability == :DRYSKIN)) ||
                  (move.pbType(battler) == :GRASS && (battler.pbPartner.ability == :SAPSIPPER || battler.pbPartner.crested == :WHISCASH)) ||
                  (move.pbType(battler) == :ELECTRIC && (battler.pbPartner.ability == :VOLTABSORB || battler.pbPartner.ability == :LIGHTNINGROD || battler.pbPartner.ability == :MOTORDRIVE)) ||
                  (move.pbType(battler) == :GROUND && (battler.pbPartner.crested == :SKUNTANK || battler.pbPartner.ability == :EARTHEATER)) # Gen 9 Mod - Added Earth Eater
              scoremult *= 2
            elsif battler.pbPartner.hp > 0 && (battler.pbPartner.hp.to_f > 0.1 * battler.pbPartner.totalhp || pbAIfaster?(move, nil, battler, battler.pbPartner)) && !(!@battle.pbOwnedByPlayer?(battler.index) && battler.name == "Spacea")
              scoremult = [(1 - 2 * mondata.scorearray[pi][moveindex] / 100.0), 0].max # multiplier to control how much to arbitrarily care about hitting partner; lower cares more
              scoremult *= 0.5 if pbAIfaster?(move, nil, battler, battler.pbPartner) && mondata.scorearray[pi][moveindex] > 50 # care more if we're faster and would knock it out before it attacks
            end
            chooseablemoves.push({ moveindex: moveindex, target: [oi, ci, pi], score: scoremult * (mondata.scorearray[ci][moveindex] + mondata.scorearray[oi][moveindex]), zmove: false })
          when :BothSides # actually targets only user side
            chooseablemoves.push({ moveindex: moveindex, target: [oi, ci], score: Math.sqrt(mondata.scorearray[ci][moveindex]**2 + mondata.scorearray[oi][moveindex]**2).round, zmove: false })
          when :Partner
            chooseablemoves.push({ moveindex: moveindex, target: [pi], score: [mondata.scorearray[ci][moveindex], mondata.scorearray[oi][moveindex]].max, zmove: false })
            [oi, ci].each do |targetindex|
              chooseablemoves.push({ moveindex: moveindex, target: [targetindex], score: mondata.scorearray[targetindex][moveindex], zmove: false })
            end
          when :OppositeOpposing
            if @battle.battlers[oi].hp > 0
              chooseablemoves.push({ moveindex: moveindex, target: [oi], score: mondata.scorearray[oi][moveindex], zmove: false })
            else
              chooseablemoves.push({ moveindex: moveindex, target: [ci], score: mondata.scorearray[ci][moveindex], zmove: false })
            end
          when :UserOrPartner
            if @battle.battlers[oi].hp > 0 && @battle.battlers[ci].hp > 0
              chooseablemoves.push({ moveindex: moveindex, target: [battler.index], score: (mondata.scorearray[ci][moveindex] + mondata.scorearray[oi][moveindex]) / 2, zmove: false })
            elsif @battle.battlers[oi].hp > 0
              chooseablemoves.push({ moveindex: moveindex, target: [battler.index], score: mondata.scorearray[oi][moveindex], zmove: false })
            else
              chooseablemoves.push({ moveindex: moveindex, target: [battler.index], score: mondata.scorearray[ci][moveindex], zmove: false })
            end
          when :DragonDarts # curse whoever made this thing
            if move.pbDragonDartTargetting(battler).length > 1
              chooseablemoves.push({ moveindex: moveindex, target: [pi], score: [mondata.scorearray[ci][moveindex], mondata.scorearray[oi][moveindex]].max, zmove: false })
              chooseablemoves.push({ moveindex: moveindex, target: [oi, ci], score: (mondata.scorearray[ci][moveindex] + mondata.scorearray[oi][moveindex]), zmove: false })
            else
              [oi, pi, ci].each do |targetindex|
                chooseablemoves.push({ moveindex: moveindex, target: [targetindex], score: mondata.scorearray[targetindex][moveindex], zmove: false })
              end
            end
        end
      else
        unless battler.pbTarget(move) == :UserOrPartner
          chooseablemoves.push({ moveindex: moveindex, target: [oi], score: mondata.scorearray[oi][moveindex], zmove: false })
        else
          chooseablemoves.push({ moveindex: moveindex, target: [battler.index], score: mondata.scorearray[oi][moveindex], zmove: false })
        end
      end
    end
    # Add a possible z-move to the choosable moves. Only if the scores for non-z move are all lower than 100
    if mondata.zmove && (chooseablemoves.all? { |array| array[:score] < 100 } || [:CONVERSION, :CELEBRATE, :SPLASH, :CLANGOROUSSOULBLAZE].include?(mondata.zmove.move))
      # find which move has been turned into z-move
      originalmove = battler.zmoves.include?(mondata.zmove) ? mondata.zmove : :NATUREPOWER
      if originalmove.is_a?(Symbol)
        originalmoveindex = battler.zmoves.find_index { |moveloop| moveloop != nil && moveloop.move == originalmove }
      elsif originalmove.is_a?(PokeBattle_Move)
        originalmoveindex = battler.zmoves.find_index(mondata.zmove)
      else
        puts "How did you fuck up this badly?"
      end
      oi = battler.pbOppositeOpposing.index # opposite opponent
      if @battle.doublebattle
        ci = battler.pbCrossOpposing.index
        if [:CONVERSION, :CELEBRATE, :SPLASH, :CLANGOROUSSOULBLAZE].include?(mondata.zmove.move)
          chooseablemoves.push({ moveindex: originalmoveindex, target: [oi, ci], score: mondata.scorearray[oi][-1] + mondata.scorearray[ci][-1], zmove: true })
        else
          [oi, ci].each { |targetindex| chooseablemoves.push({ moveindex: originalmoveindex, target: [targetindex], score: mondata.scorearray[targetindex][-1], zmove: true }) }
        end
      else
        chooseablemoves.push({ moveindex: originalmoveindex, target: [oi], score: mondata.scorearray[oi][4], zmove: true })
      end
    end
    return chooseablemoves
  end

  def coordinateActions(ai_l, ai_r, op_l, op_r) # changes some scores doesn't choose
    return if @battle.battlers[ai_l].hp == 0 || @battle.battlers[ai_r].hp == 0 || (@battle.pbIsWild? && !(@battle.battlers.any? { |battler| battler.isbossmon || battler.issossmon }))

    threatscore = threatAssessment(ai_l, ai_r, op_l, op_r)
    biggest_threat = threatscore.index(threatscore.max)
    aimon1 = @battle.battlers[ai_l]
    aimon2 = @battle.battlers[ai_r]

    # find targets of all killing moves
    killing_moves = [[], [], [], []]
    for i in [ai_l, ai_r]
      @aimondata[i].roughdamagearray.each_with_index { |array, monindex|
        next if monindex == ai_l || monindex == ai_r

        array.each_with_index { |obj, moveindex|
          if obj >= 100 && @aimondata[i].scorearray[monindex][moveindex] > 80 # killing move + not awful score
            killing_moves[i].push(monindex)
          end
        }
      }
    end
    # shape the array in something more usable
    killing_moves.map! { |arr| arr.uniq }
    killing_moves.map!.with_index { |arr, index|
      if arr.length == 2
        :both
      elsif arr[0] == op_l
        :left
      elsif arr[0] == op_r
        :right
      elsif index == op_l || index == op_r
        :_
      else
        :none
      end
    }

    # if only one of them has a killing move, make it so the other one doesn't target the same mon
    if (killing_moves[ai_l] != :none && killing_moves[ai_r] == :none) || (killing_moves[ai_r] != :none && killing_moves[ai_l] == :none)
      # battlerindexes
      ai_leader = killing_moves[ai_l] != :none ? ai_l : ai_r
      ai_follow = ai_leader ^ 2

      leader_mon = @battle.battlers[ai_leader]
      follow_mon = @battle.battlers[ai_follow]
      opp_left_mon = @battle.battlers[op_l]
      opp_righ_mon = @battle.battlers[op_r]

      # get the move it will choose
      leader_moves = findChoosableMoves(leader_mon, @aimondata[ai_leader])
      leader_moves.sort! { |a, b| b[:score] <=> a[:score] }
      bestmove = leader_moves[0][:zmove] ? @aimondata[ai_leader].zmove : leader_mon.moves[leader_moves[0][:moveindex]]

      if bestmove.betterCategory != :status && bestmove.priority == 0
        decrease_by = 1.0
        speedorder = pbMoveOrderAI()
        case speedorder
          # leader fastest and no specific way to save follower before follower attacks
          when [ai_leader, ai_follow, op_l, op_r] then decrease_by = 0.4
          when [ai_leader, op_l, op_r, ai_follow] then decrease_by = 0.4
          when [ai_leader, op_r, op_l, ai_follow] then decrease_by = 0.4
          when [ai_follow, ai_leader, op_l, op_r] then decrease_by = 0.4
          when [ai_follow, ai_leader, op_r, op_l] then decrease_by = 0.4
          when [ai_leader, ai_follow, op_r, op_l] then decrease_by = 0.4

          # leader slowest, but survives both hits of the opponent
          when [op_l, op_r, ai_follow, ai_leader] then decrease_by = 0.7 if checkAIdamage(leader_mon, opp_left_mon) + checkAIdamage(leader_mon, opp_righ_mon) < leader_mon.hp
          when [op_r, op_l, ai_follow, ai_leader] then decrease_by = 0.7 if checkAIdamage(leader_mon, opp_left_mon) + checkAIdamage(leader_mon, opp_righ_mon) < leader_mon.hp
          when [op_l, ai_follow, op_r, ai_leader] then decrease_by = 0.7 if checkAIdamage(leader_mon, opp_left_mon) + checkAIdamage(leader_mon, opp_righ_mon) < leader_mon.hp
          when [op_r, ai_follow, op_l, ai_leader] then decrease_by = 0.7 if checkAIdamage(leader_mon, opp_left_mon) + checkAIdamage(leader_mon, opp_righ_mon) < leader_mon.hp
          when [ai_follow, op_l, op_r, ai_leader] then decrease_by = 0.7 if checkAIdamage(leader_mon, opp_left_mon) + checkAIdamage(leader_mon, opp_righ_mon) < leader_mon.hp
          when [ai_follow, op_r, op_l, ai_leader] then decrease_by = 0.7 if checkAIdamage(leader_mon, opp_left_mon) + checkAIdamage(leader_mon, opp_righ_mon) < leader_mon.hp
          when [op_r, op_l, ai_leader, ai_follow] then decrease_by = 0.7 if checkAIdamage(leader_mon, opp_left_mon) + checkAIdamage(leader_mon, opp_righ_mon) < leader_mon.hp
          when [op_l, op_r, ai_leader, ai_follow] then decrease_by = 0.7 if checkAIdamage(leader_mon, opp_left_mon) + checkAIdamage(leader_mon, opp_righ_mon) < leader_mon.hp

          # leader survives a hit from the left opp before targetting their mon, and can't save follower
          when [op_l, ai_leader, ai_follow, op_r] then decrease_by = 0.7 if checkAIdamage(leader_mon, opp_left_mon) < leader_mon.hp
          when [ai_follow, op_l, ai_leader, op_r] then decrease_by = 0.7 if checkAIdamage(leader_mon, opp_left_mon) < leader_mon.hp
          when [op_l, ai_follow, ai_leader, op_r] then decrease_by = 0.7 if checkAIdamage(leader_mon, opp_left_mon) < leader_mon.hp


          # leader survives a hit from the left opp before targetting their mon, and can't save follower
          when [op_r, ai_leader, ai_follow, op_l] then decrease_by = 0.7 if checkAIdamage(leader_mon, opp_righ_mon) < leader_mon.hp
          when [ai_follow, op_r, ai_leader, op_l] then decrease_by = 0.7 if checkAIdamage(leader_mon, opp_righ_mon) < leader_mon.hp
          when [op_r, ai_follow, ai_leader, op_l] then decrease_by = 0.7 if checkAIdamage(leader_mon, opp_righ_mon) < leader_mon.hp

          # leader can save follower from taking a hit before moving follower moves, so target that slot unless that slot is unimportant
          when [ai_leader, op_l, ai_follow, op_r] then decrease_by = 0.7
          when [ai_leader, op_r, ai_follow, op_l] then decrease_by = 0.7
          when [op_l, ai_leader, op_r, ai_follow] then decrease_by = 0.7
          when [op_r, ai_leader, op_l, ai_follow] then decrease_by = 0.7

        end

        # change the targetting of the biggest target if it stops the follower from getting hit
        case speedorder
          # leader moves first, then the mon that can be killed then the follower, then the last
          when [ai_leader, op_l, ai_follow, op_r], [ai_leader, op_r, ai_follow, op_l]
            if killing_moves[ai_leader] == :both && checkAIdamage(follow_mon, @battle.battlers[speedorder[1]]) >= follow_mon.hp
              biggest_threat = speedorder[1] if threatscore[speedorder[3]] <= 2 * threatscore[speedorder[1]]
            end
          # if the leader is gonna survive a hit from the mon moving before it, but the follower isn't from the mon after it, kill the mon that moves aftere the follower
          when [op_l, ai_leader, op_r, ai_follow]
            if killing_moves[ai_leader] == :both && checkAIdamage(leader_mon, @battle.battlers[speedorder[0]]) < leader_mon.hp && checkAIdamage(follow_mon, @battle.battlers[speedorder[2]]) >= follow_mon.hp
              biggest_threat = threatscore[speedorder[0]] >= 2 * threatscore[speedorder[2]] ? speedorder[0] : speedorder[2]
            end
        end

        scoreDecrease(biggest_threat, killing_moves, decrease_by, ai_leader)
      elsif bestmove.priority > 0
        # priority moves fuck up just about everything
        biggest_threat_index = biggest_threat
        scoreDecrease(biggest_threat, killing_moves, 0.4, ai_leader)
      elsif [:AllOpposing, :AllNonUsers].include?(leader_mon.pbTarget(bestmove))
        # fuck it if i know
      end
    end

    # if both of them have killing move determine who should target who, mostly just don't target both the same
    if killing_moves[ai_l] != :none && killing_moves[ai_r] != :none
      bestchoice1 = getMaxScoreIndex(@aimondata[ai_l].scorearray)
      bestchoice2 = getMaxScoreIndex(@aimondata[ai_r].scorearray)
      bestmove1 = bestchoice1[1] == 4 ? @aimondata[ai_l].zmove : aimon1.moves[bestchoice1[1]]
      bestmove2 = bestchoice2[1] == 4 ? @aimondata[ai_r].zmove : aimon2.moves[bestchoice2[1]]
      # make sure the best move isn't a status move or switching/item

      if bestmove2.betterCategory != :status && bestmove1.betterCategory != :status
        speedorder = pbMoveOrderAI()
        targetting_done = false
        case speedorder
          when [ai_l, ai_r, op_r, op_l], [ai_r, ai_l, op_r, op_l], [ai_l, ai_r, op_l, op_r], [ai_r, ai_l, op_l, op_r] # ai,ai,player,player

          when [ai_l, op_l, ai_r, op_r], [ai_l, op_r, ai_r, op_l], [ai_r, op_l, ai_l, op_r], [ai_r, op_r, ai_l, op_l] # ai,player,ai,player
            if killing_moves == [:_, :both, :_, :both]
              @aimondata[speedorder[0]].scorearray[speedorder[3]].map! { |score| score * 0.4 }
              @aimondata[speedorder[2]].scorearray[speedorder[1]].map! { |score| score * 0.4 }
              # speedorder[0] targets speedorder[1]
              # speedorder[2] targets speedorder[3]
              targetting_done = true
            elsif speedorder == [ai_l, op_l, ai_r, op_r] && killing_moves == [:_, :both, :_, :left] ||
                  speedorder == [ai_l, op_r, ai_r, op_l] && killing_moves == [:_, :both, :_, :right] ||
                  speedorder == [ai_r, op_l, ai_l, op_r] && killing_moves == [:_, :left, :_, :both] ||
                  speedorder == [ai_r, op_r, ai_l, op_l] && killing_moves == [:_, :right, :_, :both]
              if checkAIdamage(@battle.battlers[speedorder[2]], @battle.battlers[speedorder[1]]) >= @battle.battlers[speedorder[2]].hp
                @aimondata[speedorder[0]].scorearray[speedorder[3]].map! { |score| score * 0.4 }
                @aimondata[speedorder[2]].scorearray[speedorder[1]].map! { |score| score * 0.7 }
                # speedorder[0] targets speedorder[1]
                # speedorder[2] gets score decreased for speedorder[1]
                targetting_done = true
              end
            end
          when [ai_l, op_l, op_r, ai_r], [ai_l, op_r, op_l, ai_r], [ai_r, op_l, op_r, ai_l], [ai_r, op_r, op_l, ai_l] # ai,player,player,ai
            case killing_moves
              when [:_, :both, :_, :both]
                @aimondata[speedorder[0]].scorearray[biggest_threat].map! { |score| score * 0.7 }
                @aimondata[speedorder[3]].scorearray[biggest_threat].map! { |score| score * 0.7 }
                # speedorder[0] targets biggest threat
                # speedorder[3] targets other
                targetting_done = true
              when [:_, :left, :_, :left]
                @aimondata[speedorder[0]].scorearray[op_r].map! { |score| score * 0.7 }
                @aimondata[speedorder[3]].scorearray[op_l].map! { |score| score * 0.7 }
                # speedorder[0] targets the one they can kill
                # speedorder[3] targets other
                targetting_done = true
              when [:_, :right, :_, :right]
                @aimondata[speedorder[0]].scorearray[op_r].map! { |score| score * 0.7 }
                @aimondata[speedorder[3]].scorearray[op_l].map! { |score| score * 0.7 }
                # speedorder[0] targets the one they can kill
                # speedorder[3] targets other
                targetting_done = true
            end
          when [op_l, ai_l, ai_r, op_r], [op_l, ai_r, ai_l, op_r], [op_r, ai_l, ai_r, op_l], [op_r, ai_r, ai_l, op_l] # player,ai,ai,player
            case killing_moves
              when [:_, :both, :_, :both], [:_, :left, :_, :left], [:_, :right, :_, :right]
                # don't edit the scores, who knows which mon will live
                targetting_done = true
            end
          when [op_l, ai_l, op_r, ai_r], [op_l, ai_r, op_r, ai_l], [op_r, ai_l, op_l, ai_r], [op_r, ai_r, op_l, ai_l] # player,ai,player,ai
            case killing_moves
              when [:_, :both, :_, :both]
                @aimondata[speedorder[1]].scorearray[speedorder[0]].map! { |score| score * 0.7 }
                @aimondata[speedorder[3]].scorearray[speedorder[2]].map! { |score| score * 0.7 }
                # speedorder[1] targets speedorder[2]
                # speedorder[3] targets speedorder[0]
                targetting_done = true
              when [:_, :left, :_, :left], [:_, :right, :_, :right]
                if checkAIdamage(@battle.battlers[speedorder[1]], @battle.battlers[speedorder[0]]) >= @battle.battlers[speedorder[1]].hp
                  chosen_index = killing_moves == [:_, :left, :_, :left] ? op_l : op_r
                  @aimondata[speedorder[3]].scorearray[chosen_index].map! { |score| score * 0.7 }
                  targetting_done = true
                else
                  # don't edit the scores, who knows which mon will live
                  targetting_done = true
                end
            end
          when [op_l, op_r, ai_l, ai_r], [op_r, op_l, ai_l, ai_r], [op_l, op_r, ai_r, ai_l], [op_r, op_l, ai_r, ai_l] # player,player,ai,ai
            case killing_moves
              when [:_, :both, :_, :both]
                # don't edit the scores, who knows which mon will live
                targetting_done = true
              when [:_, :left, :_, :left], [:_, :right, :_, :right]
                # don't edit the scores, who knows which mon will live
                targetting_done = true
            end
        end
        if !targetting_done
          case killing_moves
            when [:_, :both, :_, :both]
              # just target differently
              if @battle.pbRandom(2) == 0
                @aimondata[ai_l].scorearray[op_l].map! { |score| score * 0.7 }
                @aimondata[ai_r].scorearray[op_r].map! { |score| score * 0.7 }
              else
                @aimondata[ai_l].scorearray[op_l].map! { |score| score * 0.7 }
                @aimondata[ai_r].scorearray[op_r].map! { |score| score * 0.7 }
              end
            when [:_, :left, :_, :both]
              # only need to change 3 to target 2
              @aimondata[ai_r].scorearray[op_l].map! { |score| score * 0.7 }
            when [:_, :right, :_, :both]
              # only need to change 3 to target 0
              @aimondata[ai_r].scorearray[op_r].map! { |score| score * 0.7 }
            when [:_, :both, :_, :left]
              # only need to change 1 to target 2
              @aimondata[ai_l].scorearray[op_l].map! { |score| score * 0.7 }
            when [:_, :both, :_, :right]
              # only need to change 1 to target 0
              @aimondata[ai_r].scorearray[op_r].map! { |score| score * 0.7 }
            when [:_, :left, :_, :left]
              # check which has highest score move not targetting 0
              if @aimondata[ai_l].scorearray[op_l].max > @aimondata[ai_r].scorearray[op_l].max
                @aimondata[ai_l].scorearray[op_r].map! { |score| score * 0.7 }
                @aimondata[ai_r].scorearray[op_l].map! { |score| score * 0.7 }
              else
                @aimondata[ai_l].scorearray[op_l].map! { |score| score * 0.7 }
                @aimondata[ai_r].scorearray[op_r].map! { |score| score * 0.7 }
              end

            when [:_, :left, :_, :right]
            # nothing to do here
            when [:_, :right, :_, :left]
            # nothing to do here
            when [:_, :right, :_, :right]
              # check which has highest score move not targetting 2
              if @aimondata[ai_l].scorearray[op_r].max > @aimondata[ai_r].scorearray[op_r].max
                @aimondata[ai_l].scorearray[op_l].map! { |score| score * 0.7 }
                @aimondata[ai_r].scorearray[op_r].map! { |score| score * 0.7 }
              else
                @aimondata[ai_l].scorearray[op_r].map! { |score| score * 0.7 }
                @aimondata[ai_r].scorearray[op_l].map! { |score| score * 0.7 }
              end
          end
        end
      end
    end

    # Finding the best moves for both AI
    moves_1 = findChoosableMoves(aimon1, @aimondata[ai_l])
    moves_2 = findChoosableMoves(aimon2, @aimondata[ai_r])
    return if moves_1.length == 0 || moves_2.length == 0

    moves_1.sort! { |a, b| b[:score] <=> a[:score] }
    moves_2.sort! { |a, b| b[:score] <=> a[:score] }
    bestindex1 = moves_1[0][:moveindex]
    bestindex2 = moves_2[0][:moveindex]
    bestmove1 = aimon1.moves[bestindex1]
    bestmove2 = aimon2.moves[bestindex2]
    nextbest1 = moves_1.find { |scores| scores[:moveindex] != moves_1[0][:moveindex] }
    nextbest2 = moves_2.find { |scores| scores[:moveindex] != moves_2[0][:moveindex] }
    bestmoves_id = [bestmove1.move, bestmove2.move]

    # both want to use a attention-grabbing move
    if bestmoves_id.all? { |bestmove| [:FOLLOWME, :RAGEPOWDER].include?(bestmove) }
      if !nextbest1.nil? || !nextbest2.nil?
        if nextbest1.nil? || !nextbest2.nil? && nextbest1[:score] > nextbest2[:score]
          @aimondata[ai_l].scorearray.map! { |a| a.map!.with_index { |b, i| i == bestindex1 ? 0 : b } }
        else
          @aimondata[ai_r].scorearray.map! { |a| a.map!.with_index { |b, i| i == bestindex2 ? 0 : b } }
        end
      end
    end

    # one wants to use helping hand
    if :HELPINGHAND == bestmove1.move || :HELPINGHAND == bestmove2.move
      if :HELPINGHAND == bestmove1.move && bestmove2.basedamage == 0
        @aimondata[ai_l].scorearray.map! { |a| a.map!.with_index { |b, i| i == bestindex1 ? 0 : b } }
      elsif :HELPINGHAND == bestmove2.move && bestmove1.basedamage == 0
        @aimondata[ai_r].scorearray.map! { |a| a.map!.with_index { |b, i| i == bestindex2 ? 0 : b } }
      end
    end

    # both want to use the same move that affects the battlefield
    if bestmove1.move == bestmove2.move &&
       [:STEALTHROCK, :STICKYWEB, :TAILWIND, :GRAVITY, :LIGHTSCREEN, :REFLECT, :AURORAVEIL, :TRICKROOM, :WONDERROOM, :MAGICROOM, :SUNNYDAY, :RAINDANCE, :HAIL, :SANDSTORM, :SAFEGUARD, :SHADOWSKY, :CHILLYRECEPTION].include?(bestmove1.move)
      if !nextbest1.nil? && !nextbest2.nil?
        if nextbest1[:score] > nextbest2[:score]
          @aimondata[ai_l].scorearray.map! { |a| a.map!.with_index { |b, i| i == bestindex1 ? 0 : b } }
        else
          @aimondata[ai_r].scorearray.map! { |a| a.map!.with_index { |b, i| i == bestindex2 ? 0 : b } }
        end
      end
    end

    # both want to use a status move against an opponent
    if PBStuff::STATUSCONDITIONMOVE.include?(bestmove1.move) && PBStuff::STATUSCONDITIONMOVE.include?(bestmove2.move) && moves_1[0][:target].intersection(moves_2[0][:target]) != []
      nextbest1 = moves_1.find { |scores|
        scores[:moveindex] != moves_1[0][:moveindex] || scores[:target].intersection(moves_2[0][:target]) == []
      }
      nextbest2 = moves_2.find { |scores|
        scores[:moveindex] != moves_2[0][:moveindex] || scores[:target].intersection(moves_1[0][:target]) == []
      }
      if !nextbest1.nil? && !nextbest2.nil?
        if nextbest1[:score] > nextbest2[:score]
          @aimondata[ai_l].scorearray.map!.with_index do |a, moveindex|
            a.map!.with_index { |b, i|
              i == bestindex1 && nextbest1[:target].include?(moveindex) ? 0 : b
            }
          end
        else
          @aimondata[ai_r].scorearray.map!.with_index do |a, moveindex|
            a.map!.with_index { |b, i|
              i == bestindex2 && nextbest2[:target].include?(moveindex) ? 0 : b
            }
          end
        end
      end
    end

    # both want to use a confusion causing move agains an opponent
    if bestmoves_id.all? { |bestmove| PBStuff::CONFUMOVE.include?(bestmove) && ![:CHATTER, :DYNAMICPUNCH].include?(bestmove) } && moves_1[0][:target].intersection(moves_2[0][:target]) != []
      nextbest1 = moves_1.find { |scores|
        scores[:moveindex] != moves_1[0][:moveindex] || scores[:target].intersection(moves_2[0][:target]) == []
      }
      nextbest2 = moves_2.find { |scores|
        scores[:moveindex] != moves_2[0][:moveindex] || scores[:target].intersection(moves_1[0][:target]) == []
      }
      if !nextbest1.nil? && !nextbest2.nil?
        if nextbest1[:score] > nextbest2[:score]
          @aimondata[ai_l].scorearray.map!.with_index { |a, moveindex|
            a.map!.with_index { |b, i|
              i == bestindex1 && nextbest1[:target].include?(moveindex) ? 0 : b
            }
          }
        else
          @aimondata[ai_r].scorearray.map!.with_index { |a, moveindex|
            a.map!.with_index { |b, i|
              i == bestindex2 && nextbest2[:target].include?(moveindex) ? 0 : b
            }
          }
        end
      end
    end

    # both want to use other move that interferes with eachother on same mon
    if bestmoves_id.all? { |bestmove| [:ENCORE].include?(bestmove) } && moves_1[0][:target].intersection(moves_2[0][:target]) != []
      nextbest1 = moves_1.find { |scores|
        scores[:moveindex] != moves_1[0][:moveindex] || scores[:target].intersection(moves_2[0][:target]) == []
      }
      nextbest2 = moves_2.find { |scores|
        scores[:moveindex] != moves_2[0][:moveindex] || scores[:target].intersection(moves_1[0][:target]) == []
      }
      if !nextbest1.nil? && !nextbest2.nil?
        if nextbest1[:score] > nextbest2[:score]
          @aimondata[ai_l].scorearray.map!.with_index { |a, moveindex|
            a.map!.with_index { |b, i|
              i == bestindex1 && nextbest1[:target].include?(moveindex) ? 0 : b
            }
          }
        else
          @aimondata[ai_r].scorearray.map!.with_index { |a, moveindex|
            a.map!.with_index { |b, i|
              i == bestindex2 && nextbest2[:target].include?(moveindex) ? 0 : b
            }
          }
        end
      end
    end

    # one is using eq and other wants to roost
    if bestmoves_id.include?(:EARTHQUAKE) && bestmoves_id.include?(:ROOST)
      if :EARTHQUAKE == bestmove1.move
        if !pbAIfaster?(bestmove1, bestmove2, aimon1, aimon2)
          @aimondata[ai_r].scorearray.map! { |a| a.map!.with_index { |b, i| i == bestindex2 ? 0 : b } }
        end
      elsif :EARTHQUAKE == bestmove2.move
        if !pbAIfaster?(bestmove2, bestmove1, aimon2, aimon1)
          @aimondata[ai_l].scorearray.map! { |a| a.map!.with_index { |b, i| i == bestindex1 ? 0 : b } }
        end
      end
    end
  end

  def threatAssessment(ai_l, ai_r, op_l, op_r)
    # Dont care about it if one of the player mons is dead
    return [1, -1, 1, -1] if @battle.battlers[op_l].hp <= 0 && @battle.battlers[op_r].hp <= 0
    return [0, -1, 1, -1] if @battle.battlers[op_l].hp <= 0
    return [1, -1, 0, -1] if @battle.battlers[op_r].hp <= 0

    threatscore = [-1, 1.0, -1, 1.0]

    # find out which of the AI mons are still Alive
    aimons = [@battle.battlers[ai_l], @battle.battlers[ai_r]].find_all { |mon| mon && mon.hp > 0 }

    @battle.battlers.each_with_index { |opp, i|
      next if i == ai_l || i == ai_r # only opponents need to be assessed

      # Base stat total
      threatscore[i] *= pbBaseStatTotal(opp.species) / 200.0
      # Level
      threatscore[i] *= (opp.level / ((aimons.sum { |mon| mon.level }) / aimons.length))**2
      # Mega
      threatscore[i] *= 1.1 if opp.isMega?
      # Gen 9 Mod - Added Zero to Hero
      threatscore[i] *= 2.0 if opp.ability == :ZEROTOHERO
      # Boosts
      threatscore[i] *= 1 + 0.2 * opp.stages[PBStats::ATTACK] if opp.attack > opp.spatk
      threatscore[i] *= 1 + 0.2 * opp.stages[PBStats::SPATK] if opp.spatk > opp.attack
      threatscore[i] *= 1 + 0.05 * opp.stages[PBStats::DEFENSE] if aimons.any? { |mon| mon.attack > mon.spatk }
      threatscore[i] *= 1 + 0.05 * opp.stages[PBStats::SPDEF] if aimons.any? { |mon| mon.spatk > mon.attack }
      threatscore[i] *= 1 + 0.10 * opp.stages[PBStats::SPEED] if (opp.stages[PBStats::SPEED] > 0) ^ @battle.trickroom != 0
      threatscore[i] *= [1 + 0.20 * opp.stages[PBStats::ACCURACY], 0.3].max if opp.stages[PBStats::ACCURACY] < 0
      threatscore[i] *= 1 + 0.20 * opp.stages[PBStats::EVASION] if opp.stages[PBStats::EVASION] > 0
      # Opp has revealed spread move
      threatscore[i] *= 1.2 if getAIMemory(opp).any? { |moveloop| moveloop != nil && [:AllOpposing, :AllNonUsers].include?(opp.pbTarget(moveloop)) }
      # Opp has killing move
      threatscore[i] *= 1.5 if aimons.any? { |mon| checkAIdamage(opp, mon) >= mon.hp }
      # Abilities
      threatscore[i] *= aimons.sum { |mon| getAbilityDisruptScore(mon, opp) / aimons.length }
      # Speed
      threatscore[i] *= 1.5 if aimons.any? { |aimon| pbAIfaster?(nil, nil, opp, aimon) }
      threatscore[i] *= 1.1 if aimons.all? { |aimon| pbAIfaster?(nil, nil, opp, aimon) }
      # Status
      threatscore[i] *= 0.6 if opp.status == :SLEEP || (opp.status == :FROZEN && !KAIZOMOD)
      threatscore[i] *= 0.8 if opp.status == :PARALYSIS && ![:GUTS, :MARVELSCALE, :QUICKFEET].include?(opp.ability)
    }
    PBDebug.log(sprintf("Opposing threat scores : %s", threatscore.join(", "))) if $INTERNAL
    return threatscore
  end

  def getMoveScore(initialscores=[],scoreindex=-1)
    @move = pbChangeMove(@move,@attacker)
    #################### Setup ####################
    score=initialscores[scoreindex]
    @initial_scores=initialscores
    @score_index=scoreindex
    if $ai_log_data[@attacker.index].move_names.length - $ai_log_data[@attacker.index].final_score_moves.length > 0
      $ai_log_data[@attacker.index].move_names.pop()
      $ai_log_data[@attacker.index].init_score_moves.pop()
      $ai_log_data[@attacker.index].opponent_name.pop()
    end
    $ai_log_data[@attacker.index].move_names.push(sprintf("%s - %d", @move.name, @opponent.index))
    $ai_log_data[@attacker.index].init_score_moves.push(score)
    $ai_log_data[@attacker.index].opponent_name.push(@opponent.name)
    @mondata.oppitemworks = @opponent.itemWorks?
    @mondata.attitemworks = @attacker.itemWorks?
    #################### Misc. Scoring ####################
    # Type-nulling abilities
    if @move.basedamage>0
      typemod=pbTypeModNoMessages(@move.pbType(@attacker))
      $ai_log_data[@attacker.index].final_score_moves.push(typemod) if typemod<=0
      return typemod if typemod<=0
      wondercheck = typemod<=4 && @opponent.ability == :WONDERGUARD
    end
    #Hell check: Can you hit this pokemon that has an ability that nullifies your move? # Gen 9 Mod - Added myceliumMightCheck
    if @mondata.skill>=MEDIUMSKILL && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker)) &&
        ((@attacker.pbTarget(@move)==:SingleNonUser || [:RandomOpposing, :AllOpposing, :OpposingSide, :SingleOpposing].include?(@attacker.pbTarget(@move)) || (@attacker.pbTarget(@move)==:OppositeOpposing && @attacker.hasType?(:GHOST))) && @move.basedamage == 0)
      if wondercheck
        $ai_log_data[@attacker.index].final_score_moves.push(0)
        return 0
      end
      # Gen 9 Mod - Added Earth Eater
      if (@move.pbType(@attacker) == :FIRE && @opponent.nullsFire?) || (@move.pbType(@attacker) == :GRASS && @opponent.nullsGrass?) ||
        (@move.pbType(@attacker) == :WATER && @opponent.nullsWater?) || (@move.pbType(@attacker) == :ELECTRIC && @opponent.nullsElec?) ||
        (@move.pbType(@attacker) == :GROUND && @opponent.nullsGround?)
        $ai_log_data[@attacker.index].final_score_moves.push(-1)
        return -1
      end
      $ai_log_data[@attacker.index].final_score_moves.push(0) if (@opponent.ability == :MAGICBOUNCE || @opponent.pbPartner.ability == :MAGICBOUNCE) && @move.basedamage == 0 #there is not a good way to do this section
      $ai_log_data[@attacker.index].final_score_moves.push(0) if (@opponent.effects[:MagicCoat]==true || @opponent.pbPartner.effects[:MagicCoat]==true) && @move.basedamage == 0 #there is not a good way to do this section
      return -1 if (@opponent.ability == :MAGICBOUNCE || @opponent.pbPartner.ability == :MAGICBOUNCE) && @move.basedamage == 0 #there is not a good way to do this section
      return -1 if (@opponent.effects[:MagicCoat]==true || @opponent.pbPartner.effects[:MagicCoat]==true) && @move.basedamage == 0 #there is not a good way to do this section
    end
    if @move.pbType(@attacker) == :GROUND && !canGroundMoveHit?(@opponent) && @battle.FE !=:CAVE && @move.basedamage != 0
      $ai_log_data[@attacker.index].final_score_moves.push(0)
      return 0
    end
    # field based move failures (should this be a high skill check?)
    if @move.moveFieldBoost==0
      $ai_log_data[@attacker.index].final_score_moves.push(0)
      return 0
    end
    if @move.typeFieldBoost(@move.pbType(@attacker),@attacker,@opponent)==0
      $ai_log_data[@attacker.index].final_score_moves.push(0)
      return 0
    end
    #fuck
    #Priority checks
    if @move.pbIsPriorityMoveAI(@attacker) && @attacker != @opponent.pbPartner
      aifaster=pbAIfaster?()
      aifaster_partner = pbAIfaster?(nil,nil,@attacker,@opponent.pbPartner) if @battle.doublebattle && @opponent.pbPartner.hp > 0
      #if move.basedamage>0
      PBDebug.log(sprintf("Priority Check Begin")) if $INTERNAL
      aifaster ? PBDebug.log(sprintf("AI Pokemon is faster.")) : PBDebug.log(sprintf("Player Pokemon is faster.")) if $INTERNAL
      if (@battle.doublebattle || (@opponent.status!=:SLEEP && (@opponent.status!=:FROZEN || KAIZOMOD) && !@opponent.effects[:Truant] && @opponent.effects[:HyperBeam] == 0)) && !seedProtection?(@attacker) # This line might be in the wrong place, but we're trying our best here-- skip priority if opponent is incapacitated
        if score>100
          score*= @battle.doublebattle ? 1.3 : (aifaster ? 1.3 : 2)
        elsif @attacker.ability == :STANCECHANGE && !aifaster && @attacker.form == 0 && @attacker.pokemon.species == :AEGISLASH
          score*=0.7
        elsif @attacker.crested == :VESPIQUEN && !aifaster && @attacker.effects[:VespiCrest] == false
          score*=0.7
        end
        movedamage = -1
        opppri = false
        pridam = -1
        movedamage2 = -1
        opppri2 = false
        pridam2 = -1
        if !aifaster || aifaster_partner===false || getAIMemory().any? {|moveloop| moveloop!=nil && moveloop.basedamage > 0 && moveloop.pbIsPriorityMoveAI(@opponent)} || getAIMemory(@opponent.pbPartner).any? {|moveloop| moveloop!=nil && moveloop.basedamage > 0 && moveloop.pbIsPriorityMoveAI(@opponent.pbPartner)} && @battle.doublebattle
          testmemory= getAIMemory() + [PokeBattle_Move_FFF.new(@battle,@opponent, @opponent.type1)]
          testmemory= testmemory + [PokeBattle_Move_FFF.new(@battle,@opponent, @opponent.type2)] if !@opponent.type2.nil?
          for i in testmemory
            tempdam = pbRoughDamage(i,@opponent,@attacker)
            movedamage = tempdam if tempdam>movedamage
            if i.pbIsPriorityMoveAI(@opponent) && i.basedamage > 0
              opppri=true
              pridam = tempdam if tempdam>pridam
            end
          end
          testmemory= getAIMemory(@opponent.pbPartner) + [PokeBattle_Move_FFF.new(@battle,@opponent.pbPartner, @opponent.pbPartner.type1)]
          testmemory= testmemory + [PokeBattle_Move_FFF.new(@battle,@opponent.pbPartner, @opponent.pbPartner.type2)] if !@opponent.pbPartner.type2.nil?
          for i in testmemory
            tempdam = pbRoughDamage(i,@opponent.pbPartner,@attacker)
            movedamage2 = tempdam if tempdam>movedamage2
            if i.pbIsPriorityMoveAI(@opponent.pbPartner) && i.basedamage > 0
              opppri2=true
              pridam2 = tempdam if tempdam>pridam2
            end
          end
        end
        movedamage = @attacker.hp - 1 if notOHKO?(@attacker, @opponent, true)
        movedamage2 = @attacker.hp - 1 if notOHKO?(@attacker, @opponent.pbPartner, true)
        PBDebug.log(sprintf("pre-check: %d", score)) if $INTERNAL
        PBDebug.log(sprintf("Expected damage taken: %d", [movedamage, movedamage2].max)) if $INTERNAL
        scoreboost = @battle.doublebattle ? 40 : 150
        scoreboost = 30 if PBStuff::PROTECTMOVE.include?(@move.move)
        if (@attacker.pbPartner.pbHasMove?(:FOLLOWME) || @attacker.pbPartner.pbHasMove?(:RAGEPOWDER))
          scoreboost = 0
        end
        if @opponent.species == :MEWTWO && @opponent.isbossmon
          scoreboost = 0
        end
        score += scoreboost if !aifaster && (movedamage > @attacker.hp && !(@attacker.ability == :RESUSCITATION && @attacker.form == 1) || !aifaster_partner && movedamage2 > @attacker.hp && !(@attacker.ability == :RESUSCITATION && @attacker.form == 1)) && score > 1
        PBDebug.log(sprintf("post-check: %d", score)) if $INTERNAL
        if opppri
          score *= 1.1
          score *= aifaster ? 3 : 0.5 if pridam > attacker.hp
        elsif opppri2
          score *= 1.1
          score *= aifaster_partner ? 3 : 0.5 if pridam2 > attacker.hp
        end
      end
      score *= 0 if !aifaster && @opponent.effects[:TwoTurnAttack] != 0
      score *= 0 if @battle.FE == :PSYTERRAIN && !@opponent.isAirborne?
      # Gen 9 Mod - Added Armor Tail
      score *= 0 if @opponent.ability == :DAZZLING || @opponent.ability == :ARMORTAIL || @opponent.ability == :QUICKREFLEX || @opponent.ability == :QUEENLYMAJESTY || @opponent.pbPartner.ability == :DAZZLING || @opponent.pbPartner.ability == :ARMORTAIL || @opponent.pbPartner.ability == :QUICKREFLEX || @opponent.pbPartner.ability == :QUEENLYMAJESTY || ((opponent.ability == :MIRRORARMOR || opponent.pbPartner.ability == :MIRRORARMOR) && @battle.FE == :STARLIGHT)
      score *= 0.2 if (checkAImoves([:QUICKGUARD]) || checkAImoves([:QUICKGUARD], getAIMemory(@opponent.pbPartner))) && @attacker.pbTarget(move) != :User
      PBDebug.log(sprintf("Priority Check End")) if $INTERNAL
    elsif @move.priority < 0 && pbAIfaster?()
      score *= 0.9
      score *= 0.6 if initialscores[scoreindex] >= 100 && initialscores.count { |iniscore| iniscore >= 100 } > 1
      score *= 2 if @move.basedamage > 0 && @opponent.effects[:TwoTurnAttack] != 0
    end
    # Sound move checks # Gen 9 Mod - Added myceliumMightCheck
    if !@move.zmove && @move.isSoundBased?
      $ai_log_data[@attacker.index].final_score_moves.push(0) if (@opponent.ability == :SOUNDPROOF && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))) || @attacker.effects[:ThroatChop]!=0
      return 0 if (@opponent.ability == :SOUNDPROOF && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))) || @attacker.effects[:ThroatChop]!=0
      score *= 0.6 if checkAImoves([:THROATCHOP])
    end
    # Wind Move Checks
    # Gen 9 Mod - Added Wind Rider # Gen 9 Mod - Added myceliumMightCheck
    if !@move.zmove && @move.windMove?
      $ai_log_data[@attacker.index].final_score_moves.push(0) if (@opponent.ability == :WINDRIDER && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker)))
      return 0 if (@opponent.ability == :WINDRIDER && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker)))
    end

    if @opponent.ability == :DANCER
      if PBStuff::DANCEMOVE.include?(@move.move)
        score *= 0.5
        score *= 0.1 if @battle.FE == :BIGTOP || @battle.FE == :DANCEFLOOR
      end
    end
    ioncheck = false
    if @mondata.skill >= HIGHSKILL && @opponent.index != @attacker.index
      for j in getAIMemory(@opponent)
        destinycheck = true if j.move == :DESTINYBOND
        # Gen 9 Mod - Added Silk Trap and Burning Bulwark
        shieldcheck = true if j.move == :SPIKYSHIELD || j.move == :KINGSSHIELD || j.move == :BANEFULBUNKER || j.move == :OBSTRUCT || j.move == :SILKTRAP || j.move == :BURNINGBULWARK
      end
      if @move.basedamage > 0 && (![:FUTURESIGHT, :DOOMDESIRE].include?(@move.move) || @move.priority < 0)
        if @opponent.effects[:DestinyBond]
          score *= 0.2
        else
          score *= 0.7 if !pbAIfaster?(@move) && destinycheck
        end
      end
      ioncheck = checkAImovesAllOpponents([:IONDELUGE, :PLASMAFISTS])
      if ioncheck && @move.type == :NORMAL
        score *= 0.3 if [:LIGHTNINGROD, :VOLTABSORB, :MOTORDRIVE].include?(@opponent.ability) || @opponent.pbPartner.ability == :LIGHTNINGROD
      end
      score *= 0.2 if checkAImovesAllOpponents([:WIDEGUARD]) && [:AllOpposing, :AllNonUsers].include?(@attacker.pbTarget(@move))
      score *= 0.2 if checkAImovesAllOpponents([:POWDER]) && @move.pbType(@attacker) == :FIRE
    end
    # If opponent about to use a recover move before being killed, check damage vs them again
    if checkAIhealing && !pbAIfaster?(@move) && @mondata.skill >= BESTSKILL && @move.basedamage > 0
      newhp = [((@opponent.totalhp + 1) / 2) + @opponent.hp, @opponent.totalhp].min
      score *= [pbRoughDamage / newhp.to_f, 1.1].min
    end
    # Check for moves that can be nullified by any mon in doubles
    if @battle.doublebattle && [:SingleNonUser, :RandomOpposing, :SingleOpposing, :OppositeOpposing].include?(@attacker.pbTarget(@move)) && !(@attacker.ability == :PROPELLERTAIL || @attacker.ability == :STALWART)
      if @move.pbType(@attacker) == :ELECTRIC || (ioncheck && @move.type == :NORMAL)
        if @opponent.pbPartner.ability == :LIGHTNINGROD
          $ai_log_data[@attacker.index].final_score_moves.push(0)
          return -1
        end

        score *= 0.3 if @attacker.pbPartner.ability == :LIGHTNINGROD
      elsif @move.pbType(@attacker) == :WATER
        if @opponent.pbPartner.ability == :STORMDRAIN
          $ai_log_data[@attacker.index].final_score_moves.push(0)
          return -1
        end

        score *= 0.3 if @attacker.pbPartner.ability == :STORMDRAIN
      end
    end
    if !@move.nil? && !@move.zmove && @move.highCritRate?
      if !(@opponent.ability == :SHELLARMOR || @opponent.ability == :BATTLEARMOR || @attacker.effects[:LaserFocus] > 0)
        boostercount = 0
        if @move.pbIsPhysical?()
          boostercount += @opponent.stages[PBStats::DEFENSE] if @opponent.stages[PBStats::DEFENSE] > 0
          boostercount -= @attacker.stages[PBStats::ATTACK] if @attacker.stages[PBStats::ATTACK] < 0
        elsif @move.pbIsSpecial?()
          boostercount += @opponent.stages[PBStats::SPDEF] if @opponent.stages[PBStats::SPDEF] > 0
          boostercount -= @attacker.stages[PBStats::SPATK] if @attacker.stages[PBStats::SPATK] < 0
        end
        score *= (1.05**boostercount) if hasgreatmoves()
      end
    end
    # If you have two moves that kill, use one that doesn't consume your item (gems only rn)
    if hasgreatmoves() && @attacker.item
      score *= 0.85 if @attacker.item == :POWERHERB && (PBStuff::TWOTURNMOVE + PBStuff::CHARGEMOVE).include?(@move.move)
      score *= 0.9 if $cache.items[@attacker.item].checkFlag?(:typeboost) == @move.type && $cache.items[@attacker.item].checkFlag?(:gem)
    end
    if Rejuv && @battle.FE == :SWAMP
      if ([:ATTACKORDER, :STRINGSHOT].include?(@move.move) || PBStuff::HEALFUNCTIONS.include?(@move.function))
        statarray = [1, 1, 1, 1, 1, 1, 1]
        statarray.unshift(0) # this is required to make the next line work correctly
        # Start by eliminating pointless stats
        minidrop = 1.05
        for i in 1...statarray.length
          if @opponent.pbCanReduceStatStage?(i)
            minidrop += (@opponent.ability == :COMPETITIVE || @opponent.ability == :DEFIANT || @opponent.ability == :CONTRARY) ? -0.1 : 0.05
          end
        end
        score *= minidrop
      end
    end
    # Contact move checks
    # Gen 9 Mod - Added Punching Glove
    if !@move.zmove && @move.contactMove? && !(@attacker.item == :PROTECTIVEPADS || (@attacker.item == :PUNCHINGGLOVE && move.punchMove?)) && @attacker.ability != :LONGREACH
      contactscore = 1.0
      contactscore *= @attacker.hp < 0.2 * @attacker.totalhp ? 0.5 : 0.85 if (@mondata.oppitemworks && @opponent.item == :ROCKYHELMET) || shieldcheck
      case @opponent.ability
        when :EFFECTSPORE then contactscore *= 0.75
        when :PERISHBODY then contactscore *= [:DIMENSIONAL, :HAUNTED, :INFERNAL].include?(@battle.FE) ? 0.5 : 0.75 unless @battle.FE == :HOLY
        when :FLAMEBODY then contactscore *= 0.75 if @attacker.pbCanBurn?(false)
        when :STATIC then contactscore *= 0.75 if @attacker.pbCanParalyze?(false)
        when :POISONPOINT then contactscore *= 0.75 if @attacker.pbCanPoison?(false)
        when :CUTECHARM then contactscore *= 0.8 if @attacker.effects[:Attract] < 0 && initialscores.length > 0 && initialscores[scoreindex] < 110
        when :ROUGHSKIN, :IRONBARBS then contactscore *= @attacker.hp < 0.2 * @attacker.totalhp ? 0.5 : 0.85
        when :GOOEY, :TANGLINGHAIR, :COTTONDOWN
          if @attacker.pbCanReduceStatStage?(PBStats::SPEED)
            contactscore *= 0.9
            contactscore *= 0.8 if pbAIfaster?()
          end
        # Gen 9 Mod - Added Lingering Aroma
        when :MUMMY, :WANDERINGSPIRIT, :LINGERINGAROMA
          if !((PBStuff::FIXEDABILITIES).include?(@attacker.ability)) && !(@attacker.ability == :MUMMY || @attacker.ability == :SHIELDDUST || @attacker.ability == :LINGERINGAROMA)
            mummyscore = getAbilityDisruptScore(@opponent, @attacker)
            # Gen 9 Mod - Added Ability Shield
            mummyscore = 1 if (@mondata.oppitemworks && @opponent.item == :ABILITYSHIELD)
            mummyscore = mummyscore < 2 ? 2 - mummyscore : 0
            contactscore *= mummyscore
          end
        # Gen 9 Mod - Added Toxic Debris
        when :TOXICDEBRIS then contactscore *= 0.8 if @attacker.pbOwnSide.effects[:ToxicSpikes] < 2
      end
      contactscore *= 0.8 if @opponent.species == :AEGISLASH && !checkAImoves([:KINGSSHIELD]) && (@move.pbIsPhysical?() || @battle.FE == :FAIRYTALE)
      contactscore *= 0.5 if checkAImoves([:KINGSSHIELD]) && !PBStuff::RATESHARERS.include?(@opponent.lastMoveUsed) && (@move.pbIsPhysical?() || @battle.FE == :FAIRYTALE)
      contactscore *= 0.7 if checkAImoves([:BANEFULBUNKER]) && !PBStuff::RATESHARERS.include?(@opponent.lastMoveUsed) && @attacker.pbCanPoison?(false)
      contactscore *= 0.6 if checkAImoves([:SPIKYSHIELD]) && !PBStuff::RATESHARERS.include?(@opponent.lastMoveUsed) && @attacker.hp < 0.3 * @attacker.totalhp
      # Gen 9 Mod - Added Silk Trap and Burning Bulwark
      contactscore *= 0.7 if checkAImoves([:SILKTRAP]) && !PBStuff::RATESHARERS.include?(@opponent.lastMoveUsed) && @attacker.pbCanReduceStatStage?(PBStats::SPEED)
      if checkAImoves([:BURNINGBULWARK]) && !PBStuff::RATESHARERS.include?(@opponent.lastMoveUsed) && @attacker.pbCanBurn?(false)
        if @attacker.attack > @attacker.spatk
          contactscore *= 0.6
        else
          contactscore *= 0.8
        end
      end
      # Gen 9 Mod - Added Shield Dust & Covert Cloak
      contactscore *= 1.1 if @attacker.ability == :POISONTOUCH && @opponent.pbCanPoison?(false) && !(@opponent.ability == :SHIELDDUST || @opponent.item == :COVERTCLOAK)
      contactscore *= 1.1 if @attacker.ability == :PICKPOCKET && @opponent.item && !@battle.pbIsUnlosableItem(@opponent,@opponent.item) && @attacker.item.nil?
      contactscore *= 0.1 if seedProtection?(@opponent) && !PBStuff::PROTECTIGNORINGMOVE.include?(@move.move)
      #this could be increased for moves that hit more than twice, but this should be sufficiently strong enough to deter move usage regardless
      contactscore = contactscore**2 if @move.pbIsMultiHit
      score *= contactscore
    end
    # This is for seeds that activated at the start of the turn
    if @move.basedamage > 0 && seedProtection?(@opponent) && !PBStuff::PROTECTIGNORINGMOVE.include?(@move.move)
      score *= 0.1
    end
    # If you have a move that kills, use it.
    if @move.basedamage == 0 && hasgreatmoves()
      maxdam = checkAIdamage()
      if maxdam > 0 && maxdam < (@attacker.hp * 0.3)
        score *= 0.6
      else
        score *= 0.2 ### highly controversial, revert to 0.1 if shit sucks
      end
    end
    # Don't use powder moves if they don't do anything
    if PBStuff::POWDERMOVES.include?(@move.move) && (@opponent.hasType?(:GRASS) || @opponent.ability == :OVERCOAT || (@mondata.oppitemworks && @opponent.item == :SAFETYGOGGLES))
      $ai_log_data[@attacker.index].final_score_moves.push(0)
      return 0
    end
    # Prefer damaging moves if AI has no more Pokémon
    if @attacker.pbNonActivePokemonCount == 0
      if @mondata.skill >= MEDIUMSKILL && !(@mondata.skill >= HIGHSKILL && @opponent.pbNonActivePokemonCount > 0)
        if @move.basedamage == 0
          PBDebug.log("[Not preferring status move]") if $INTERNAL
          score *= 0.9
        elsif @opponent.hp <= @opponent.totalhp / 2.0
          PBDebug.log("[Preferring damaging move]") if $INTERNAL
          score *= 1.1
        end
      end
    end
    # Don't prefer attacking the opponent if they'd be semi-invulnerable
    if @opponent.effects[:TwoTurnAttack]!=0 && @mondata.skill>=HIGHSKILL
      invulmove=@opponent.effects[:TwoTurnAttack]
      if (@move.accuracy>0 || @move.function==0xA5 || @move.zmove && @move.basedamage > 0 || @move.move == :WHIRLWIND) && (PBStuff::TWOTURNMOVE.include?(invulmove) || @opponent.effects[:SkyDrop]) &&
          pbAIfaster?(@move,nil,@attacker,@opponent) && @attacker.ability != :NOGUARD && @opponent.ability != :NOGUARD && !(@attacker.ability==:FAIRYAURA && @battle.FE == :FAIRYTALE)
        miss = true
        if @mondata.skill>=BESTSKILL
          case invulmove
            when :FLY, :BOUNCE then miss = false if PBStuff::AIRHITMOVES.include?(@move.move) || @move.move == :WHIRLWIND
            when :DIG then miss = false if @move.move == :EARTHQUAKE || @move.move == :MAGNITUDE || @move.move == :FISSURE
            when :DIVE then miss = false if @move.move == :SURF || @move.move == :WHIRLPOOL
            when :SKYDROP then miss = false if PBStuff::AIRHITMOVES.include?(@move.move)
            end
          if @opponent.effects[:SkyDrop]
            miss = false if PBStuff::AIRHITMOVES.include?(@move.move)
          end
          $ai_log_data[@attacker.index].final_score_moves.push(0) if miss
          return 0 if miss
        else
          $ai_log_data[@attacker.index].final_score_moves.push(0)
          return 0
        end
      end
    end
    # Gen 9 Mod - Don't prefer attacking a Tatsugiri inside Dondozo's mouth
    if @opponent.effects[:Commander]
      $ai_log_data[@attacker.index].final_score_moves.push(0)
      return 0
    end
    # Don't prefer an attack if the opponent has revealed a mon that would be immume to it
    switchableparty = @battle.pbParty(@opponent.index).find_all.with_index {|mon,monindex| @battle.pbCanSwitch?(@opponent.index,monindex,false,true)}
    oppparty = getAIKnownParty(@opponent)
    oppparty = switchableparty.intersection(oppparty)
    if oppparty.any? { |oppmon,moves| @move.pbTypeModifierNonBattler(@move.pbType(@attacker),@attacker,oppmon) <= 1 }
      score *= 0.9
    end
    # Pick a good move for the Choice items
    if (@mondata.attitemworks && (@attacker.item == :CHOICEBAND || @attacker.item == :CHOICESPECS || @attacker.item == :CHOICESCARF)) || @attacker.ability == :GORILLATACTICS || (@attacker.debutanteCheck)
      if @move.basedamage==0 && @move.function!=0xF2 && @move.function!=0x13d && @move.function!=0xb4 # Trick, parting shot and sleep talk
        score*=0.1
      else
        score *= 0.8 if oppparty.any? { |oppmon,moves| @move.pbTypeModifierNonBattler(@move.pbType(@attacker),@attacker,oppmon) == 0 }
      end
      score *= (@move.accuracy/100.0) if @move.accuracy > 0
      score *= 0.9 if @move.pp <= 5
      score *= 0.1 if [:FIRSTIMPRESSION, :FAKEOUT].include?(@move.move) && (@opponent.pbNonActivePokemonCount > 0 || @initial_scores[@score_index] < 100)
    end
    # If user is frozen, prefer a move that can thaw the user
      if (@attacker.status== :FROZEN && !KAIZOMOD) && @mondata.skill>=MEDIUMSKILL
      if PBStuff::UNFREEZEMOVE.include?(@move.move)
        score+=30
      else
        $ai_log_data[@attacker.index].final_score_moves.push(0) if @attacker.moves.any? {|moveloop| moveloop!=nil && (PBStuff::UNFREEZEMOVE).include?(moveloop.move)}
        return 0 if @attacker.moves.any? {|moveloop| moveloop!=nil && (PBStuff::UNFREEZEMOVE).include?(moveloop.move)}
      end
    end
    # If target is frozen, don't prefer moves that could thaw them
    if @opponent.status== :FROZEN && !KAIZOMOD
      score *= 0.1 if @move.pbType(@attacker) == :FIRE
    end
    # If opponent is dark type and attacker has prankster, don't use status moves on them
    if @mondata.skill>=MEDIUMSKILL && @attacker.ability == :PRANKSTER && (@opponent.hasType?(:DARK) && @battle.FE != :BEWITCHED)
      #if @move.basedamage==0 && @move.priority>-1 && (@attacker.pbTarget(@move)==:SingleNonUser || (@attacker.pbTarget(@move) && 0x486 != 0))
      if @move.basedamage==0 && @move.priority>-1 && ((@attacker.pbTarget(@move) && 0x486 != 0)) # Fixes Prankster on Opponents, so uh, tread lightly # Gen 9 Mod - Prankster Fix
        $ai_log_data[@attacker.index].final_score_moves.push(0)
        return 0
      end
    end
    # If move changes field consider value of changing it
    if @mondata.skill>=BESTSKILL
      fieldmove = @battle.field.moveData(@move.move)
      if fieldmove && fieldmove[:fieldchange]
        attacker = @attacker
        change_conditions = @battle.field.fieldChangeData
        if change_conditions[fieldmove[:fieldchange]]
          handled = eval(change_conditions[fieldmove[:fieldchange]])
        else
          handled = true
        end
        if handled  #don't continue if conditions to change are not met
          currentfieldscore = getFieldDisruptScore(@attacker,@opponent,@battle.FE) # the higher the better for opp
          newfieldscore = getFieldDisruptScore(@attacker,@opponent,fieldmove[:fieldchange])
          score*= Math.sqrt(currentfieldscore/newfieldscore)
        end
      end
    end
    #Weigh scores against accuracy
    accuracy=pbRoughAccuracy(@move,@attacker,@opponent)
    moddedacc = (accuracy + 100)/2.0
      score*=moddedacc/100.0
    # Avoid shiny wild pokemon if you're an AI partner
    if @battle.pbIsWild?
      score *= 0.1 if @attacker.index == 2 && @opponent.pokemon.isShiny?
    end
    if @opponent.pbPartner.species == :MEWTWO && opponent.pbPartner.isbossmon
      score *= 0.1
    end
    #################### Function Code Scoring ####################
    miniscore=1.0
    case @move.function
      when 0x00 # No effect
        if @mondata.skill >= BESTSKILL && @battle.FE != :INDOOR
          case @battle.FE
          when :ICY
            if @move.move == :TECTONICRAGE
              if @battle.field.backup== :WATERSURFACE # Water Surface
                currentfieldscore = getFieldDisruptScore(@attacker,@opponent,@battle.FE) # the higher the better for opp
                newfieldscore = getFieldDisruptScore(@attacker,@opponent,:WATERSURFACE)
                miniscore = currentfieldscore/newfieldscore
              else
                miniscore*=1.2 if @opponent.pbNonActivePokemonCount>2
                miniscore*=0.8 if @attacker.pbNonActivePokemonCount>2
              end
            end
          when :MIRROR
            miniscore*=2 if @move.move == :DAZZLINGGLEAM && mirrorNeverMiss
            miniscore*=0.3 if @move.move == :BOOMBURST || @move.move == :HYPERVOICE
          when :FLOWERGARDEN2,:FLOWERGARDEN3,:FLOWERGARDEN4,:FLOWERGARDEN5
            if (@move.move == :CUT || @move.move == :XSCISSOR) && @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN,2,5)
              miniscore*= pbPartyHasType?(:GRASS) || pbPartyHasType?(:BUG) ? 0.3 : 2.0
            end
            if @move.move==:PETALBLIZZARD && @battle.FE == :FLOWERGARDEN5
              miniscore*=1.5 if @battle.doublebattle
            end
          when :VOLCANICTOP
            miniscore*=volcanoeruptioncode() if @move.move == :PRECIPICEBLADES
          end
        end
      when 0x01 # Splash
        if @mondata.skill >= BESTSKILL && @battle.FE == :WATERSURFACE
          miniscore = antistatcode([0,0,0,0,0,1,0],initialscores[scoreindex])
        end
        if @move.zmove
          miniscore*= selfstatboost([1,1,1,1,1,0,0]) if @move.move == :CELEBRATE
          miniscore*= selfstatboost([3,0,0,0,0,0,0]) if @move.move == :SPLASH
        end
      when 0x02 # Struggle
        miniscore*=0.2
      when 0x03 # Sleep, Dark Void, Grass Whistle, Sleep Powder, Spore, Relic Song, Lovely Kiss, Sing, Hypnosis, # Gen 9 Mod - Wicked Torque
        miniscore = sleepcode()
        miniscore *= 1.3 if pbAIfaster?(@move)
        if @mondata.skill >= BESTSKILL
          miniscore*= 2 if @move.move==:SLEEPPOWDER && @battle.FE == :FLOWERGARDEN5 && @battle.doublebattle
        end
      when 0x04 # Yawn
        miniscore = sleepcode()
      when 0x05 # Poison, Gunk Shot, Sludge Wave, Sludge Bomb, Poison Jab, Sludge, Poison Tail, Smog, Poison Sting, Poison Gas, Poison Powder, # Gen 9 Mod - Noxious Torque
        miniscore = poisoncode()
        if @mondata.skill >= BESTSKILL
          if @battle.FE == :WATERSURFACE || @battle.FE == :UNDERWATER # Water Surface/Underwater
            if @move.move==:SLUDGEWAVE
                 miniscore*=1.75 if pbPartyHasType?(:POISON) && !pbPartyHasType?(:WATER)
              miniscore*=0 if !@attacker.hasType?(:POISON) && !@attacker.hasType?(:STEEL) && @battle.pbPokemonCount(@battle.pbParty(@opponent.index))==1 && @battle.field.counter==1
              end
          end
          if @battle.FE == :MISTY # Misty Terrain
            if @move.move==:SMOG || @move.move==:POISONGAS
              miniscore*=1.75 if pbPartyHasType?(:POISON) && !pbPartyHasType?(:FAIRY)
            end
            if @move.move==:POISONGAS
              if pbPartyHasType?(:POISON) && !pbPartyHasType?(:FAIRY)
                score = 15
                miniscore = 1.0
              end
            end
            end
        end
      when 0x06 # Toxic, Poison Fang, # Gen 9 Mod - Malignant Chain
        miniscore = poisoncode()
        if @move.move==:TOXIC
          miniscore*=1.1 if @attacker.hasType?(:POISON)
        end
      when 0x07 # Paralysis, Dragon breath, Bolt Strike, Zap Cannon, Thunderbolt, Discharge, Thunder Punch, Spark, Thunder Shock, Thunder Wave, Force Palm, Lick, Stun Spore, Body Slam, Glare, Nuzzle, Wildbolt Storm, # Gen 9 Mod - Combat Torque
        miniscore = paracode()
      when 0x08 # Thunder
        miniscore = paracode()
        miniscore *= thunderboostcode()
        miniscore *= nevermisscode(initialscores[scoreindex]) if @battle.pbWeather== :RAINDANCE
      when 0x09 # Paralysis + Flinch, Thunder Fang
        miniscore = paracode()
        miniscore *= flinchcode()
      when 0x0A # Burn Blue Flare, Fire Blast, Heat Wave, Inferno, Sacred Fire, Searing Shot, Flamethrower, Blae kick, Lava Plume, Fire Punch, Flame Wheel, Ember, Will-O-Wist, Scald, Steam Eruption, Sandsear Storm, # Gen 9 Mod - Blazing Torque
        miniscore = burncode()
        if @mondata.skill >= BESTSKILL
          if move.move==:SCALD || move.move==:STEAMERUPTION
            if @battle.FE == :ICY # Icy Field
              currentfieldscore = getFieldDisruptScore(@attacker,@opponent,@battle.FE) # the higher the better for opp
              newfieldscore = getFieldDisruptScore(@attacker,@opponent,:WATERSURFACE)
              miniscore*= Math.sqrt(currentfieldscore/newfieldscore)
            end
          end
          if move.move == :LAVAPLUME
            if @battle.FE == :VOLCANICTOP
              miniscore*=volcanoeruptioncode()
            end
          end
        end
      when 0x0B # Burn + Flinch, Fire Fang
        miniscore = burncode()
        miniscore *= flinchcode()
      when 0x0C # Freeze, Ice Beam, Ice Punch, Powder Snow, Freeze-Dry
        miniscore = KAIZOMOD ? frostbitecode() : freezecode()
      when 0x0D # Blizzard Freeze
        miniscore = KAIZOMOD ? frostbitecode() : freezecode()
        miniscore *= nevermisscode(initialscores[scoreindex]) if @battle.pbWeather== :HAIL
      when 0x0E # Freeze + Flinch, Ice Fang
        miniscore = KAIZOMOD ? frostbitecode() : freezecode()
        miniscore *= flinchcode()
        if @mondata.skill >= BESTSKILL
          if @battle.FE == :GLITCH # Glitch
            miniscore*=1.2
          end
        end
      when 0x0F # Flinch, Dark Pulse, Bite, Rolling Kick, Air Slash, Astonish, Needle Arm, Hyper Fang, Headbutt, Extrasensory, Zen Headbutt, Heart Stamp, Rock Slide, Iron Head, Waterfall, Zing Zap
        miniscore = flinchcode()
      when 0x10 # Stomp, Steamroller, Dragon Rush
        miniscore = flinchcode()
      when 0x11 # Snore
        miniscore = flinchcode() if @attacker.status== :SLEEP
        score = 0 if @attacker.status!=:SLEEP
      when 0x12 # Fake Out
        if @attacker.turncount==0 && !(@opponent.effects[:Substitute] > 0 || @opponent.ability == :INNERFOCUS || secondaryEffectNegated?())
          #usually this would be saved as miniscore, but we directly add to the score
          score *= flinchcode()
          score+=115 if score>1
          score*=0.7 if @battle.doublebattle
          score*=1.5 if (@attacker.pbPartner.pbHasMove?(:TRICKROOM) && @battle.trickroom == 0) || (@attacker.pbPartner.pbHasMove?(:TAILWIND) || @attacker.pbOwnSide.effects[:Tailwind] == 0)
          score*=1.1 if (@attacker.itemWorks? && @attacker.item == :NORMALGEM)
          score*=1.5 if @attacker.ability == :UNBURDEN
          score*=0.3 if checkAImoves([:ENCORE])
        elsif @attacker.turncount!=0
          score=0
        end
      when 0x13 # Confusion, Signal Beam, Dynamic Punch, Chatter, Confuse Ray, Rock Climb, Dizzy Punch, Supersonic, Sweet Kiss, Teeter Dance, Psybeam, Water Pulse, Strange Steam, # Gen 9 Mod - Magical Torque
        miniscore = confucode()
        if @mondata.skill >= BESTSKILL
          if move.move==:SIGNALBEAM
            miniscore*=2 if @battle.FE == :MIRROR && mirrorNeverMiss  # Mirror Arena
          end
          if move.move==:SWEETKISS
            miniscore*=0.2 if @battle.FE == :FAIRYTALE && @opponent.status== :SLEEP # Fairy Tale
          end
        end
        if @battle.FE == :DANCEFLOOR
          statarray = [0,1,0,0,0,0,0] if @mondata.skill >= BESTSKILL && @move.move == :TEETERDANCE
          miniscore = oppstatdrop(statarray)
        end
      when 0x14 # Chatter
      when 0x15 # Hurricane
        miniscore = confucode()
        miniscore *= thunderboostcode()
        miniscore *= nevermisscode(initialscores[scoreindex]) if @battle.pbWeather== :RAINDANCE
      when 0x16 # Attract
        miniscore = attractcode()
      when 0x17 # Tri Attack
        miniscore = (burncode() + paracode() + (KAIZOMOD ? frostbitecode() : freezecode())) / 3
      when 0x18 # Refresh
        miniscore = refreshcode()
      when 0x19 # Aromatherapy, Heal Bell
        miniscore = partyrefreshcode()
      when 0x1a # Safeguard
        #dont use safeguard.
        if @attacker.pbOwnSide.effects[:Safeguard]<=0
          if pbAIfaster?(@move) && @attacker.nil? && !@mondata.roles.include?(:STATUSABSORBER)
            score+=50 if checkAImoves([:SPORE])
          end
          #uggggh fine, i guess you are my little guardchamp
          if !@battle.opponent.is_a?(Array)
            if (@battle.opponent.trainertype==:CAMERUPT)
              score+=150
            end
          end
        end
      when 0x1b # Psycho Shift
        miniscore = psychocode()
      when 0x1c # Howl, Sharpen, Meditate, Meteor Mash, Metal Claw, Power-Up Punch
        statarray = [1,0,0,0,0,0,0]
        statarray = [3,0,0,0,0,0,0] if @mondata.skill >= BESTSKILL && @move.move==:MEDITATE && (@battle.FE == :RAINBOW || @battle.FE == :ASHENBEACH)
        statarray = [2,0,2,0,0,0,0] if @mondata.skill >= BESTSKILL && ((@move.move==:MEDITATE && @battle.FE == :PSYTERRAIN) || @move.move == :HOWL && @battle.FE == :COLOSSEUM)
        statarray = [2,0,0,0,0,0,0] if @mondata.skill >= BESTSKILL && @move.move == :HOWL && (@battle.FE == :COLOSSEUM || @battle.ProgressiveFieldCheck(PBFields::CONCERT))
        miniscore = selfstatboost(statarray)
      when 0x1d # Harden, Steel Wing, Withdraw, Psyshield Bash
        statarray = [0,1,0,0,0,0,0]
        statarray = [0,1,0,1,0,0,0] if @move.move==:PSYSHIELDBASH && @battle.FE == :PSYTERRAIN
        miniscore = selfstatboost(statarray)
      when 0x1e # Defense Curl
        miniscore = selfstatboost([0,1,0,0,0,0,0])
        score*=1.3 if @attacker.pbHasMove?(:ROLLOUT) && @attacker.effects[:DefenseCurl]==false
      when 0x1f # Flame Charge, Esper Wing, # Gen 9 Mod - Aqua Step, Trailblaze
        statarray = [0,0,0,0,1,0,0]
        statarray = [0,0,0,0,2,0,0] if @move.move==:TRAILBLAZE && @battle.FE == :FOREST
        miniscore = selfstatboost(statarray)
      when 0x20 # Charge Beam, Fiery Dance
        miniscore = selfstatboost([0,0,1,0,0,0,0])
      when 0x21 # Charge
        miniscore = selfstatboost([0,0,0,1,0,0,0])
        # Gen 9 Mod - Charge lasts until the user uses an electric move.
        miniscore*=1.5 if @attacker.moves.any?{|moveloop| moveloop!=nil && moveloop.pbType(@attacker)==:ELECTRIC} && @attacker.effects[:Charge]==true
      when 0x22 # Double Team
        statarray = [0,0,0,0,0,0,1]
        statarray = [0,0,0,0,0,0,2] if @mondata.skill >= BESTSKILL && @move.move==:DOUBLETEAM && @battle.FE == :MIRROR
        miniscore = selfstatboost(statarray)
      when 0x23 # Focus Energy
        miniscore = focusenergycode()
        miniscore*= 1.5 if @mondata.skill >= BESTSKILL && @battle.FE == :ASHENBEACH # Ashen Beach
      when 0x24 # Bulk Up
        miniscore = selfstatboost([1,1,0,0,0,0,0])
        miniscore = selfstatboost([2,2,0,0,0,0,0]) if @mondata.skill >= BESTSKILL && @battle.FE == :CROWD
      when 0x25 # Coil
        statarray = [1,1,0,0,0,1,0]
        statarray = [2,2,0,0,0,2,0] if @mondata.skill >= BESTSKILL && (@battle.FE == :GRASSY || (Rejuv && @battle.FE == :DRAGONSDEN))
        miniscore = selfstatboost(statarray)
      when 0x26 # Dragon Dance
        statarray = [1,0,0,0,1,0,0]
        statarray = [2,0,0,0,2,0,0] if @mondata.skill >= BESTSKILL && (@battle.FE == :BIGTOP || @battle.FE == :DRAGONSDEN || @battle.FE == :DANCEFLOOR)
        miniscore = selfstatboost(statarray)
      when 0x27 # Work Up
        statarray = [1,0,1,0,0,0,0]
        statarray = [2,0,2,0,0,0,0] if @battle.ProgressiveFieldCheck(PBFields::CONCERT) || @battle.FE == :CROWD || @battle.FE == :CITY
        miniscore = selfstatboost(statarray)
      when 0x28 # Growth
        statarray = [1,0,1,0,0,0,0]
        if @mondata.skill >= BESTSKILL
          statarray = [2,0,2,0,0,0,0] if @battle.FE == :GRASSY || @battle.FE == :FOREST || @battle.pbWeather== :SUNNYDAY || @battle.FE == :FLOWERGARDEN3
          statarray = [3,0,3,0,0,0,0] if @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN,4,5) # Flower Garden
        end
        miniscore = selfstatboost(statarray)
      when 0x29 # Hone Claws
        miniscore = selfstatboost([1,0,0,0,0,1,0])
      when 0x2a # Cosmic Power, Defend Order
        statarray = [0,1,0,1,0,0,0]
        statarray = [0,2,0,2,0,0,0] if @mondata.skill >= BESTSKILL && @move.move==:COSMICPOWER && [:MISTY,:RAINBOW,:HOLY,:STARLIGHT,:COSMICPOWER,:PSYTERRAIN].include?(@battle.FE)
        statarray = [0,2,0,2,0,0,0] if @mondata.skill >= BESTSKILL && @move.move==:DEFENDORDER && @battle.FE == :FOREST
        miniscore = selfstatboost(statarray)
      when 0x2b # Quiver Dance
        statarray = [0,0,1,1,1,0,0]
        statarray = [0,0,2,2,2,0,0] if @mondata.skill >= BESTSKILL && (@battle.FE == :BIGTOP || @battle.FE == :DANCEFLOOR)
        miniscore = selfstatboost(statarray)
      when 0x2c # Calm Mind
        statarray = [0,0,1,1,0,0,0]
        statarray = [0,0,2,2,0,0,0] if @mondata.skill >= BESTSKILL && (@battle.FE == :CHESS || @battle.FE == :ASHENBEACH || @battle.FE == :PSYTERRAIN)
        miniscore = selfstatboost(statarray)
      when 0x2d # Ancient Power, Silver Wind, Ominous Wind
        miniscore = selfstatboost([1,1,1,1,1,0,0])
      when 0x2e # Swords Dance
        statarray = [2,0,0,0,0,0,0]
        statarray = [3,0,0,0,0,0,0] if @mondata.skill >= BESTSKILL && @move.move==:SWORDSDANCE && [:BIGTOP,:FAIRYTALE,:DANCEFLOOR,:COLOSSEUM].include?(@battle.FE)
        miniscore = selfstatboost(statarray)
      when 0x2f # Iron Defense, Acid Armor, Barrier, Diamond Storm
        statarray = [0,2,0,0,0,0,0]
        statarray = [0,3,0,0,0,0,0] if @mondata.skill >= BESTSKILL && (@move.move==:IRONDEFENSE && @battle.FE == :FACTORY) || (@move.move==:ACIDARMOR && [:CORROSIVE,:CORROSIVEMIST,:MURKWATERSURFACE,:FAIRYTALE,:CONCERT1,:CONCERT2,:CONCERT3,:CONCERT4].include?(@battle.FE))
        miniscore = selfstatboost(statarray)
      when 0x30 # Agility, Rock Polish
        statarray = [0,0,0,0,2,0,0]
        statarray = [0,0,0,0,3,0,0] if @mondata.skill >= BESTSKILL && @move.move==:ROCKPOLISH && @battle.FE == :ROCKY
        statarray = [1,0,1,0,2,0,0] if @mondata.skill >= BESTSKILL && @move.move==:ROCKPOLISH && @battle.FE == :CRYSTALCAVERN
        miniscore = selfstatboost(statarray)
      when 0x31 # Autotomize
        statarray = [0,0,0,0,2,0,0]
        statarray = [0,0,0,0,3,0,0]  if @mondata.skill >= BESTSKILL && [:FACTORY,:CITY,:DEEPEARTH].include?(@battle.FE)
        miniscore = selfstatboost(statarray)
        miniscore*=1.5 if checkAImoves([:LOWKICK,:GRASSKNOT])
        miniscore*=0.5 if checkAImoves([:HEATCRASH,:HEAVYSLAM])
        miniscore*=0.7 if @attacker.pbHasMove?(:HEATCRASH) || @attacker.pbHasMove?(:HEAVYSLAM)
      when 0x32 # Nasty Plot
        statarray = [0,0,2,0,0,0,0]
        statarray = [0,0,3,0,0,0,0] if @mondata.skill >= BESTSKILL && [:CHESS,:PSYTERRAIN,:INFERNAL,:BACKALLEY].include?(@battle.FE)
        miniscore = selfstatboost(statarray)
      when 0x33 # Amnesia
        statarray = [0,0,0,2,0,0,0]
        miniscore = selfstatboost(statarray)
        miniscore *= 2 if @mondata.skill >= BESTSKILL && @battle.FE == :GLITCH
      when 0x34 # Minimize
        miniscore = selfstatboost([0,0,0,0,0,0,2])
      when 0x35 # Shell Smash
        miniscore = selfstatboost([2,0,2,0,2,0,0])
        miniscore*= selfstatdrop([0,1,0,1,0,0,0],score) if !(@mondata.attitemworks && @attacker.item == :WHITEHERB) # Gen 9 Mod - Slight edit to more cleanly, I think.
        if (@mondata.attitemworks && @attacker.item == :WHITEHERB)
          miniscore*=1.3
        else
          miniscore*=0.8
        end
      when 0x36 # Shift Gear
        statarray = [1,0,0,0,2,0,0]
        statarray = [2,0,0,0,2,0,0] if @mondata.skill >= BESTSKILL && [:FACTORY,:CITY].include?(@battle.FE)
        miniscore = selfstatboost(statarray)
      when 0x37 # Acupressure
        miniscore = selfstatboost([2,0,0,0,0,0,0]) +selfstatboost([0,2,0,0,0,0,0]) + selfstatboost([0,0,2,0,0,0,0]) +selfstatboost([0,0,0,2,0,0,0]) +selfstatboost([0,0,0,0,2,0,0]) +selfstatboost([0,0,0,0,0,2,0])+ selfstatboost([0,0,0,0,0,0,2])
        miniscore/=7
      when 0x38 # Cotton Guard
        miniscore = selfstatboost([0,3,0,0,0,0,0])
      when 0x39 # Tail Glow
        miniscore = selfstatboost([0,0,3,0,0,0,0])
      when 0x3a # Belly Drum
        statarray = [6,0,0,0,0,0,0]
        statarray = [6,1,0,1,0,0,0] if @mondata.skill >= BESTSKILL && @battle.FE == :BIGTOP
        miniscore = selfstatboost(statarray) ** 1.4 #More extreme scoring
        miniscore *= 0.3 if !@attacker.moves.any?{|moveloop| moveloop!=nil && moveloop.basedamage > 0 && moveloop.pbIsPriorityMoveAI(@attacker)} && !pbAIfaster?()
        miniscore *= 1.2 if @attacker.turncount<1
        miniscore = 1 if (@attacker.hp.to_f)/@attacker.totalhp <= 0.5
      when 0x3b # Superpower
        statarray = [1,1,0,0,0,0,0]
        if @attacker.ability == :CONTRARY
          miniscore = selfstatboost(statarray)
        else
          miniscore = selfstatdrop(statarray,score)
          miniscore *= 1.5 if [:MOXIE, :CHILLINGNEIGH, :ASONECHILLING].include?(@attacker.ability)
        end
      when 0x3c # Close Combat, Dragon Ascent, Headlong Rush, # Gen 9 Mod - Armor Cannon
        statarray = [0,1,0,1,0,0,0]
        if @attacker.ability == :CONTRARY
          miniscore = selfstatboost(statarray)
        else
          miniscore = selfstatdrop(statarray,score)
        end
      when 0x3d # V-Create
        statarray = [0,1,0,1,1,0,0]
        if @attacker.ability == :CONTRARY
          miniscore = selfstatboost(statarray)
        else
          miniscore = selfstatdrop(statarray,score)
        end
      when 0x3e # Hammer Arm, Ice Hammer
        statarray = [0,0,0,0,1,0,0]
        if @attacker.ability == :CONTRARY || @battle.trickroom > 2
          miniscore = selfstatboost(statarray)
        else
          miniscore = selfstatdrop(statarray,score)
        end
      when 0x3f # Overheat, Draco Meteor, Leaf Storm, Psycho Boost, Flear Cannon
        statarray = [0,0,2,0,0,0,0]
        if @attacker.ability == :CONTRARY
          miniscore = selfstatboost(statarray)
        else
          miniscore = selfstatdrop(statarray,score)
          miniscore *=1.3 if @attacker.ability == :SOULHEART
        end
      when 0x40 # Flatter
        if @opponent.ability == :CONTRARY
          miniscore = oppstatdrop(@battle.FE == :COLOSSEUM ? [0, 0, 2, 0, 0, 0, 0] : [0, 0, 1, 0, 0, 0, 0])
        else
          miniscore = oppstatboost(@battle.FE == :COLOSSEUM ? [0, 0, 2, 0, 0] : [0, 0, 1, 0, 0], true)
        end
      when 0x41 # Swagger
        if @opponent.ability == :CONTRARY
          miniscore = oppstatdrop(@battle.FE == :COLOSSEUM ? [3, 0, 0, 0, 0, 0, 0] : [2, 0, 0, 0, 0, 0, 0])
        else
          miniscore = oppstatboost(@battle.FE == :COLOSSEUM ? [3, 0, 0, 0, 0] : [2, 0, 0, 0, 0], true)
        end
      when 0x42 # Growl, Aurora Beam, Baby-Doll Eyes, Play Nice, Play Rough, Lunge, Trop Kick, # Gen 9 Mod - Chilling Water
        statarray = [1,0,0,0,0,0,0]
        statarray = [1,0,1,0,0,0,0] if @mondata.skill >= BESTSKILL && @battle.FE == :HAUNTED && @move.move == :BITTERMALICE
        statarray = [2,0,0,0,0,0,0] if @mondata.skill >= BESTSKILL && @battle.ProgressiveFieldCheck(PBFields::CONCERT)
        miniscore=oppstatdrop(statarray)
        if @mondata.skill >= BESTSKILL
          miniscore*=selfstatboost([0,0,0,0,1,0,0]) if @move.move==:LUNGE && @battle.FE == :ICY
          miniscore*=2 if @move.move==:AURORABEAM && mirrorNeverMiss && @battle.FE == :MIRROR
          miniscore*=(KAIZOMOD ? frostbitecode() : freezecode()) if Rejuv && (@battle.FE == :ICY || @battle.FE == :SNOWYMOUNTAIN) && @move.move == :BITTERMALICE
        end
      when 0x43 # Tail Whip, Crunch, Rock Smash, Crush Claw, Leer, Iron Tail, Razor Shell, Fire Lash, Liquidation, Shadow Bone
        miniscore=oppstatdrop([0,1,0,0,0,0,0])
      when 0x44 # Rock Tomb, Electroweb, Low Sweep, Bulldoze, Mud Shot, Glaciate, Icy Wind, Constrict, Bubble Beam, Bubble, # Gen 9 Mod - Pounce
        statarray = [0,0,0,0,1,0,0]
        statarray = [0,0,0,0,2,0,0] if Rejuv && ((@move.move == :STRUGGLEBUG && @battle.FE == :SWAMP) || (@battle.FE == :ELECTERRAIN && @move.move == :ELECTROWEB))
        miniscore=oppstatdrop(statarray)
        if @move.move == :BULLDOZE
          if @mondata.skill >= BESTSKILL
            if @battle.FE == :ICY # Icy Field
              if @battle.field.backup== :WATERSURFACE # Water Surface
                currentfieldscore = getFieldDisruptScore(@attacker,@opponent,@battle.FE) # the higher the better for opp
                newfieldscore = getFieldDisruptScore(@attacker,@opponent,:WATERSURFACE)
                miniscore = currentfieldscore/newfieldscore
              else
                miniscore*=1.2 if @opponent.pbNonActivePokemonCount>2
                miniscore*=0.8 if @attacker.pbNonActivePokemonCount>2
              end
            end
            if @battle.FE == :CAVE
              if @attacker.ability != :ROCKHEAD && @attacker.ability != :BULLETPROOF && @attacker.ability != :STALWART
                miniscore*=0.7
                miniscore *= 0.3 if @battle.field.counter >=1
              end
            end
            if @battle.FE == :VOLCANICTOP
              miniscore*=volcanoeruptioncode()
            end
          end
        end
      when 0x45 # Snarl, Struggle Bug, Mist Ball, Confide, Moonblast, Mystical Fire
        statarray = [0,0,1,0,0,0,0]
        statarray = [0,0,2,0,0,0,0] if @mondata.skill >= BESTSKILL && ((@move.move == :SNARL && [:FROZENDIMENSION,:BACKALLEY].include?(@battle.FE)) || (Rejuv && @move.move == :STRUGGLEBUG && @battle.FE == :SWAMP))
        miniscore=oppstatdrop(statarray)
      when 0x46 # Psychic, Bug Buzz, Focus Blast, Shadow Ball, Energy Ball, Earth Power, Acid, Luster Purge, Flash Cannon
        miniscore=oppstatdrop([0,0,0,1,0,0,0])
        if @mondata.skill >= BESTSKILL
          miniscore*=2 if (@move.move==:FLASHCANNON || @move.move==:LUSTERPURGE) && mirrorNeverMiss && @battle.FE == :MIRROR
          miniscore*=volcanoeruptioncode() if @battle.FE == :VOLCANICTOP && @move.move == :EARTHPOWER
        end
      when 0x47 # Sand Attack, Night Daze, Leaf Tornado, Mod Bomb, Mud-Slap, Flash, Smokescreen, Kinesis, Mirror Shot, Muddy Water, Octazooka
        statarray = [0,0,0,0,0,1,0]
        if @mondata.skill >= BESTSKILL
          statarray = [0,0,0,0,0,2,0] if (@move.move==:SANDATTACK && (@battle.FE == :ASHENBEACH || @battle.FE == :DESERT))
          statarray = [0,0,0,0,0,2,0] if @move.move==:FLASH && ([:DARKCRYSTALCAVERN,:SHORTCIRCUIT,:MIRROR,:STARLIGHT,:NEWWORLD,:DARKNESS1].include?(@battle.FE))
          statarray = [0,0,0,0,0,2,0] if @move.move==:SMOKESCREEN && [:BURNING,:CORROSIVEMIST,:VOLCANIC,:VOLCANICTOP,:BACKALLEY,:CITY].include?(@battle.FE)
          statarray = [0,0,0,0,0,2,0] if (@move.move==:KINESIS && (@battle.FE == :PSYTERRAIN || @battle.FE == :ASHENBEACH))
        end
        miniscore=oppstatdrop(statarray)
        if @mondata.skill >= BESTSKILL
          miniscore*=selfstatboost([2,0,2,0,0,0,0]) if @move.move==:KINESIS && @battle.FE == :PSYTERRAIN
          miniscore*=2 if @move.move==:MIRRORSHOT && mirrorNeverMiss && @battle.FE == :MIRROR
          miniscore*=0.7 if @move.move==:LEAFTORNADO && @battle.FE == :ASHENBEACH
        end
        if move.move==:MUDDYWATER
          miniscore*=0.7 if @battle.FE == :SUPERHEATED # Superheated
          if @battle.FE == :DRAGONSDEN # Dragon's Den
            miniscore*= pbPartyHasType?(:FIRE) || pbPartyHasType?(:DRAGON) ? 0 : 1.5
          end
        end
      when 0x48 # Sweet Scent
        statarray = [0,0,0,0,0,0,1]
        if @mondata.skill >= BESTSKILL
          statarray = [0,1,0,1,0,0,1] if @battle.FE == :MISTY || @battle.FE == :FLOWERGARDEN3
          statarray = [0,2,0,2,0,0,2] if @battle.FE == :FLOWERGARDEN4
          statarray = [0,3,0,3,0,0,3] if @battle.FE == :FLOWERGARDEN5
        end
        miniscore*=oppstatdrop(statarray)
      when 0x49 # Defog
        miniscore = defogcode()
      when 0x4a # Tickle
        miniscore = oppstatdrop([1,1,0,0,0,0,0])
      when 0x4b # Feather Dance, Charm
        statarray = [2,0,0,0,0,0,0]
        statarray = [3,0,0,0,0,0,0] if @mondata.skill >= BESTSKILL && @move.move == :FEATHERDANCE && @battle.FE == :BIGTOP
        statarray = [2,0,2,0,0,0,0] if @mondata.skill >= BESTSKILL && @move.move == :FEATHERDANCE && @battle.FE == :DANCEFLOOR
        miniscore = oppstatdrop(statarray)
      when 0x4c # Screech
        statarray = [0,2,0,0,0,0,0]
        statarray = [0,3,0,0,0,0,0] if @mondata.skill >= BESTSKILL && @battle.ProgressiveFieldCheck(PBFields::CONCERT)
        miniscore = oppstatdrop(statarray)
      when 0x4d # Scary Face, String Shot, Cotton Spore
        statarray = [0,0,0,0,2,0,0]
        statarray = [0,0,0,0,4,0,0] if @mondata.skill >= BESTSKILL && @move.move == :SCARYFACE && @battle.FE == :HAUNTED
        miniscore = oppstatdrop(statarray)
      when 0x4e # Captivate # Gen 9 Mod - Added myceliumMightCheck
        agender=@attacker.gender
        ogender=@opponent.gender
        if (((agender==2 || ogender==2 || agender==ogender) && !KAIZOMOD) || @opponent.effects[:Attract]>=0 || ((@opponent.ability == :OBLIVIOUS || @opponent.ability == :AROMAVEIL || @opponent.pbPartner.ability == :AROMAVEIL) && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))))
          miniscore = 0
        else
          miniscore = oppstatdrop([0,0,0,2,0,0,0])
        end
      when 0x4f # Acid Spray, Seed Flare, Metal Sound, Fake Tears, Lumina Crash
        statarray = [0,0,0,2,0,0,0]
        statarray = [0,0,0,3,0,0,0] if @mondata.skill >= BESTSKILL && @move.move==:METALSOUND && (@battle.FE == :FACTORY || @battle.FE == :SHORTCIRCUIT || @battle.ProgressiveFieldCheck(PBFields::CONCERT))
        statarray = [0,0,0,3,0,0,0] if @mondata.skill >= BESTSKILL && @move.move==:FAKETEARS && @battle.FE == :BACKALLEY
        miniscore = oppstatdrop(statarray)
      when 0x50 # Clear Smog
        miniscore = oppstatrestorecode()
        miniscore *= nevermisscode(initialscores[scoreindex])
      when 0x51 # Haze
        miniscore = hazecode()
      when 0x52 # Power Swap
        miniscore = statswapcode(PBStats::ATTACK,PBStats::SPATK)
      when 0x53 # Guard Swap
        miniscore = statswapcode(PBStats::DEFENSE,PBStats::SPDEF)
      when 0x54 # Heart Swap
        boostarray,droparray = psychupcode()
        buffscore = selfstatboost(boostarray.clone) - selfstatdrop(droparray.clone,score)
        dropscore = oppstatdrop(boostarray.clone) - selfstatboost(droparray.clone)
        miniscore = buffscore + dropscore
        miniscore = 25 if miniscore == 0 && @battle.FE == :NEWWORLD
        miniscore *= splitcode(PBStats::HP) if @battle.FE == :NEWWORLD
      when 0x55 # Psych Up
        boostarray,droparray = psychupcode()
        boostarray[3] += 2 if @mondata.skill >= BESTSKILL && @battle.FE == :PSYTERRAIN
        actualopp = @opponent
        @opponent = firstOpponent() if @opponent.index == @attacker.pbPartner.index
        miniscore = selfstatboost(boostarray) - selfstatdrop(droparray.clone,score)
        stagecounter=boostarray.sum - droparray.sum
        miniscore*= 1.3 if stagecounter>=3
        miniscore*= [1,refreshcode()].max if @mondata.skill >= BESTSKILL && @battle.FE == :ASHENBEACH
        @opponent = actualopp
      when 0x56 # Mist
        miniscore = mistcode()
        fieldscore = 1
        if @attacker.item!=:EVERSTONE && @battle.canChangeFE?(:MISTY)
          fieldscore=getFieldDisruptScore(@attacker,@opponent)
          fieldscore*=1.3 if pbPartyHasType?(:FAIRY)
          fieldscore*=1.3 if @opponent.hasType?(:DRAGON) && !@attacker.hasType?(:FAIRY)
          fieldscore*=0.5 if @attacker.hasType?(:DRAGON)
          fieldscore*=0.5 if @opponent.hasType?(:FAIRY)
          fieldscore*=1.5 if @attacker.hasType?(:FAIRY) && @opponent.spatk>@opponent.attack
          fieldscore*=2   if @mondata.attitemworks && @attacker.item == :AMPLIFIELDROCK
        end
        score*=0 if miniscore<=1 && fieldscore<=1
        miniscore*= fieldscore
      when 0x57 # Power Trick
        miniscore = powertrickcode()
      when 0x58 # Power Split
        miniscore = splitcode(PBStats::ATTACK)
      when 0x59 # Guard Split
        miniscore = splitcode(PBStats::DEFENSE)
      when 0x5a # Pain Split
        miniscore = splitcode(PBStats::HP)
      when 0x5b # Tailwind
        miniscore = tailwindcode()
        if @mondata.skill>=BESTSKILL
          if @battle.FE == :MOUNTAIN || @battle.FE == :SNOWYMOUNTAIN || @battle.FE == :SKY || @battle.FE == :VOLCANICTOP # Mountain/Snowy Mountain
            miniscore*=1.5
            miniscore*=1.5**@battle.pbParty(@attacker.index).count {|mon| mon && mon.hp>0 && mon.hasType?(:FLYING)}
          end
        end
      when 0x5c # Mimic
        miniscore = mimicsketchcode([0x02, 0x14, 0x5C, 0x5D, 0xB6],false) # Struggle, Chatter, Mimic, Sketch, Metronome
      when 0x5d # Sketch
        miniscore = mimicsketchcode([0x02, 0x14, 0x5D],true) #Struggle, Chatter, Sketch
      when 0x5e # Conversion
        miniscore = typechangecode(@attacker.moves[0].type)
        miniscore*=0.3 if @battle.field.conversion==1
        if @attacker.item!=:EVERSTONE && @battle.canChangeFE?(:GLITCH)
          minimini = getFieldDisruptScore(@attacker,@opponent)
          minimini = 1 + (minimini - 1) / 2 if @battle.field.conversion!=2
          miniscore*=minimini
        end
        if @move.zmove
          miniscore*= selfstatboost([1,1,1,1,1,0,0]) if @move.move == :CONVERSION
        end
      when 0x5f # Conversion2
        for i in @opponent.moves
          next if i.nil?
          atype=i.pbType(@attacker) if i.move==@opponent.lastMoveUsed
        end
        miniscore = 0
        if atype
          resistedtypes = PBTypes.typeResists(atype)
          for type in resistedtypes
            miniscore += (typechangecode(type) / resistedtypes.length)
          end
        end
        miniscore*=0.3 if @battle.field.conversion==2
        if @battle.canChangeFE?(:GLITCH)
          minimini = getFieldDisruptScore(@attacker,@opponent)
          minimini = 1 + (minimini - 1) / 2 if @battle.field.conversion!=1
          miniscore*=minimini
        end
      when 0x60 # Camouflage
        type = :NORMAL
        type = @battle.field.mimicry
        miniscore = typechangecode(type)
      when 0x61 # Soak
        miniscore = opptypechangecode(:WATER)
      when 0x62 # Reflect Type
        miniscore1 = typechangecode(@opponent.type1)
        miniscore2 = typechangecode(@opponent.type2)
        miniscore = [miniscore1,miniscore2].max
      when 0x63 # Simple Beam
        miniscore = abilitychangecode(:SIMPLE)
      when 0x64 # Worry Seed
        miniscore = abilitychangecode(:INSOMNIA)
        miniscore *= oppstatdrop([1,0,0,0,0,0,0]) if Rejuv && @battle.FE == :GRASSY
      when 0x65 # Role Play
        miniscore = roleplaycode()
      when 0x66 # Entrainment
        score = entraincode(score)
      when 0x67 # Skill Swap
        miniscore = skillswapcode()
      when 0x68 #Gastro Acid
        miniscore = gastrocode()
      when 0x69 # Transform
        miniscore = transformcode()
      #when 0x6A # Sonicboom
      #when 0x6B # Dragon Rage
      #when 0x6C # Super Fang, Nature Madness
      #when 0x6D # Seismic Toss, Night Shade
      when 0x6e # Endeavor
        miniscore = endeavorcode()
      when 0x70 # Fissure, Sheer Cold, Guillotine, Horn Drill
        miniscore = ohkode()
        if @mondata.skill >= BESTSKILL
          if @move.move == :FISSURE
            if @battle.FE == :ICY # Icy Field
              if @battle.field.backup== :WATERSURFACE # Water Surface
                currentfieldscore = getFieldDisruptScore(@attacker,@opponent,@battle.FE) # the higher the better for opp
                newfieldscore = getFieldDisruptScore(@attacker,@opponent,:WATERSURFACE)
                miniscore = currentfieldscore/newfieldscore
              else
                miniscore*=1.2 if @opponent.pbNonActivePokemonCount>2
                miniscore*=0.8 if @attacker.pbNonActivePokemonCount>2
              end
            end
          end
        end
      when 0x71..0x73 # Counter, Mirror Coat, Metal Burst
        miniscore = counterattackcode()
        miniscore*= Math.sqrt(selfstatboost([0,1,0,1,0,0,1])) if @mondata.skill >= BESTSKILL && @battle.FE == :MIRROR && @move.move==:MIRRORCOAT
      when 0x74 # Flame Burst
        miniscore *= 1.1 if @battle.doublebattle
      when 0x75 # Surf
        if @mondata.skill >= BESTSKILL
          miniscore*=0.7 if @battle.FE == :SUPERHEATED && @move.move == :SURF
          miniscore*= (pbPartyHasType?(:DRAGON) || pbPartyHasType?(:FIRE)) ? 0 : 1.5  if @battle.FE == :DRAGONSDEN && @move.move == :SURF
          miniscore*=volcanoeruptioncode() if @battle.FE == :VOLCANICTOP && @move.move == :MAGMADRIFT
        end
      when 0x76 # Earthquake
        if @mondata.skill >= BESTSKILL
          if @battle.FE == :ICY # Icy Field
            if @battle.field.backup== :WATERSURFACE # Water Surface
              currentfieldscore = getFieldDisruptScore(@attacker,@opponent,@battle.FE) # the higher the better for opp
              newfieldscore = getFieldDisruptScore(@attacker,@opponent,:WATERSURFACE)
              miniscore = currentfieldscore/newfieldscore
            else
              miniscore*=1.2 if @opponent.pbNonActivePokemonCount>2
              miniscore*=0.8 if @attacker.pbNonActivePokemonCount>2
            end
          end
          if @battle.FE == :CAVE && @move.move==:EARTHQUAKE
            if @attacker.ability != :ROCKHEAD && @attacker.ability != :BULLETPROOF || @attacker.ability != :STALWART
              miniscore*=0.7
              miniscore *= 0.3 if @battle.field.counter >=1
            end
          end
          if @battle.FE == :VOLCANICTOP
            miniscore=volcanoeruptioncode()
          end
        end
      when 0x77 # Gust
      when 0x78 # Twister
        miniscore = flinchcode()
        miniscore*=0.7 if @mondata.skill >= BESTSKILL && @battle.FE == :ASHENBEACH
      #when 0x79 # Fusion Bolt, Fusion Flare, Venoshock
      when 0x7c # Smelling Salts
        if @opponent.status== :PARALYSIS  && @opponent.effects[:Substitute]<=0
          score*=0.8
          score*=0.5 if @opponent.speed>@attacker.speed && @opponent.speed/2.0<@attacker.speed
        end
      when 0x7d # Wake-up Slap
        if @opponent.status== :SLEEP && @opponent.effects[:Substitute]<=0
          score*=0.8
          score*=0.3 if @attacker.ability == :BADDREAMS || @attacker.pbHasMove?(:DREAMEATER) || @attacker.pbHasMove?(:NIGHTMARE)
          score*=1.3 if checkAImoves([:SLEEPTALK, :SNORE])
        end
      #when 0x7E..0x80 # Facade, Hex, Brine
      when 0x81 # Revenge, Avalanche
        miniscore = revengecode()
      when 0x82 # Assurance
        score*=1.5 if !pbAIfaster?(@move)
      when 0x83 # Round
        score*=1.5 if @battle.doublebattle && @attacker.pbPartner.pbHasMove?(:ROUND)
      when 0x84 # Payback
        score*=2 if !pbAIfaster?(@move)
      #when 0x85..0x87 # Retaliate, Acrobatics, Weather Ball
      when 0x88 # Pursuit
        miniscore = pursuitcode()
        if @attacker.stages[PBStats::SPEED]!=6 && score>=100
          miniscore*=1.5
          miniscore*=2 if pbAIfaster?(@move)
        end
      #when 0x89..0x8a # Return, Frustration
      when 0x8B # Water Spout, Eruption
        if !pbAIfaster?(@move)
          original_power = [(150*(@attacker.hp.to_f)/@attacker.totalhp),1.0].max
          actual_power = [(150*(@attacker.hp.to_f - checkAIdamage())/@attacker.totalhp),1.0].max
          score*= actual_power / original_power
        end
        if @mondata.skill >= BESTSKILL
          if @move.move==:WATERSPOUT
            score*=0.7 if @battle.FE == :SUPERHEATED # Superheated
          end
        end
      #when 0x8C..0x90 # Crush Grip, Wring Out, Gyro Ball, Stored Power, Pwer Trip, Punishment, Hidden Power
      when 0x91 # Fury Cutter
        miniscore = echocode()
        miniscore *= (1 + 0.15 * @attacker.stages[PBStats::ACCURACY])
        miniscore *= (1 - 0.08 * @opponent.stages[PBStats::EVASION])
        miniscore*=0.8 if checkAImoves(PBStuff::PROTECTMOVE)
      when 0x92 # Echoed Voice
        miniscore = echocode()
      when 0x93 # Rage
        if @battle.FE != :DIMENSIONAL && @battle.FE != :FROZENDIMENSION
          score*=1.2 if @attacker.attack>@attacker.spatk
          score*=1.3 if @attacker.hp==@attacker.totalhp
          score*=1.3 if checkAIdamage()<(@attacker.hp/4.0)
        else
          statarray = [1,0,0,0,0,0,0]
          miniscore = selfstatboost(statarray)
        end
      when 0x94 # Present
        score*=1.2 if @opponent.hp==@opponent.totalhp
      when 0x95 # Magnitude
        if @mondata.skill >= BESTSKILL
          if @battle.FE == :ICY # Icy Field
            if @battle.field.backup== :WATERSURFACE # Water Surface
              currentfieldscore = getFieldDisruptScore(@attacker,@opponent,@battle.FE) # the higher the better for opp
              newfieldscore = getFieldDisruptScore(@attacker,@opponent,:WATERSURFACE)
              miniscore = currentfieldscore/newfieldscore
            else
              miniscore*=1.2 if @opponent.pbNonActivePokemonCount>2
              miniscore*=0.8 if @attacker.pbNonActivePokemonCount>2
            end
          end
          if @battle.FE == :CAVE
            if @attacker.ability != :ROCKHEAD && @attacker.ability != :BULLETPROOF || @attacker.ability != :STALWART
              miniscore*=0.7
              miniscore *= 0.3 if @battle.field.counter >=1
            end
          end
          if @battle.FE == :VOLCANICTOP
            miniscore=volcanoeruptioncode()
          end
        end
      when 0x96 # Natural Gift
        score *= 0 if @attacker.item.nil? || !pbIsBerry?(@attacker.item) || @attacker.ability == :KLUTZ || @battle.state.effects[:MagicRoom] > 0 || @attacker.effects[:Embargo] > 0 || @attacker.pbOwnSide.effects[:EmbargoSide] > 0 || [:UNNERVE, :ASONECHILLING, :ASONEGRIM].include?(@opponent.ability)
      when 0x97 # Trump Card
        score*=1.2 if @attacker.hp==@attacker.totalhp
        score*=1.3 if checkAIdamage()<(@attacker.hp/3.0)
      when 0x98 # Reversal, Flail
        if !pbAIfaster?(@move)
          score*=1.1
          score*=1.3 if @attacker.hp<@attacker.totalhp
        end
      #when 0x99..0x9b # Electro Ball, Low Kick, Grass Knot, Heat Crash, Heavy Slam
      when 0x9c # Helping Hand
        miniscore = helpinghandcode()
      when 0x9d # Mud Sport
        miniscore = mudsportcode()
        miniscore*= !pbPartyHasType?(:ELECTRIC) ? 2 : 0.3 if @battle.FE == :ELECTERRAIN
      when 0x9e # Water Sport
        miniscore = watersportcode()
        miniscore*= !pbPartyHasType?(:FIRE) ? 2 : 0 if @battle.FE == :BURNING
        if @battle.FE == :SUPERHEATED
          miniscore*=0.7
          miniscore*= !pbPartyHasType?(:FIRE) ? 1.8 : 0
        elsif @battle.FE == :GRASSY || @battle.FE == :FOREST || @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN)
          miniscore*=3 if !@attacker.hasType?(:FIRE) && @opponent.hasType?(:FIRE)
          miniscore*=0.5 if pbPartyHasType?(:FIRE)
          if pbPartyHasType?(:GRASS) || pbPartyHasType?(:BUG)
            miniscore*=2
            miniscore*=3 if @battle.FE == :FLOWERGARDEN5
          end
        end
      #when 0x9f # Judgement, Techno Blast, Multi-Attack
      when 0xa0 # Frost Breath, Storm Throw, Wicked Blow
        miniscore = permacritcode(initialscores[scoreindex])
      when 0xa1 # Lucky Chant
        score+=20 if @attacker.pbOwnSide.effects[:LuckyChant]==0  && @attacker.ability != :BATTLEARMOR || @attacker.ability != :SHELLARMOR && (@opponent.effects[:FocusEnergy]>1 || @opponent.effects[:LaserFocus]>0)
      when 0xa2 # Reflect
        miniscore = screencode()
        miniscore+= [0,selfstatboost([0,0,0,0,0,0,1])-1].max if  @mondata.skill >=BESTSKILL && @battle.FE == :MIRROR
      when 0xa3 # Light Screen
        miniscore = screencode()
        miniscore+= [0,selfstatboost([0,0,0,0,0,0,1])-1].max if  @mondata.skill >=BESTSKILL && @battle.FE == :MIRROR
      when 0xa4 # Secret Power
        miniscore = secretcode()
      when 0xa5 # Shock Wave, Feint Attack, Aura Sphere, Vital Throw, Aerial Ace, Shadow Punch, Swift, Magnet Bomb, Disarming Voice, Smart Strike, False Surrender, # Gen 9 Mod - Kowtow Cleave
        miniscore = nevermisscode(initialscores[scoreindex])
        miniscore *= tauntcode() if @move.move == :FALSESURRENDER && @mondata.skill >= BESTSKILL && @battle.FE == :CHESS
      when 0xa6 # Lock On, Mind Reader
        miniscore = lockoncode()
        if @battle.FE == :PSYTERRAIN && @move.move == :MINDREADER
          miniscore*=selfstatboost([0,0,2,0,0,0,0])
          score+=10 if @attacker.stages[PBStats::SPATK]<6
        end
      when 0xa7 # Foresight, Odor Sleuth
        miniscore = forecode5me()
      when 0xa8 # Miracle Eye
        miniscore = miracode()
        if @battle.FE == :PSYTERRAIN || @battle.FE == :HOLY || @battle.FE == :FAIRYTALE
          score+=10 if @attacker.stages[PBStats::SPATK]<6
          miniscore*=selfstatboost([0,0,2,0,0,0,0])
        end
      when 0xa9 # Chip Away, Sacred Sword, Darkest Lariat
        miniscore = chipcode()
      when 0xaa # Protect, Detect
        miniscore = protectcode()
      when 0xab # Quick Guard
        if (@opponent.ability == :GALEWINGS && (@opponent.hp >= @opponent.totalhp / 2 || @battle.FE == :SKY || ([:MOUNTAIN, :SNOWYMOUNTAIN, :VOLCANICTOP].include?(@battle.FE) && @battle.pbWeather == :STRONGWINDS))) || (@opponent.ability == :PRANKSTER && (!@attacker.hasType?(:DARK) || @battle.FE == :BEWITCHED)) || checkAIpriority()
          miniscore = specialprotectcode()
        else
          miniscore = 0
        end
      when 0xac # Wide Guard
        if getAIMemory().any? { |moveloop| moveloop != nil && [:AllOpposing, :AllNonUsers].include?(@opponent.pbTarget(moveloop)) }
          miniscore = specialprotectcode()
          if @battle.FE == :CORROSIVEMIST
            miniscore *= 2 if checkAImoves([:HEATWAVE, :LAVAPLUME, :ERUPTION, :MINDBLOWN])
          end
          if @battle.FE == :CAVE
            miniscore *= 2 if checkAImoves(PBFields::QUAKEMOVES)
          end
          if @battle.FE == :MIRROR
            miniscore *= 2 if (checkAImoves([:MAGNITUDE, :EARTHQUAKE, :BULLDOZE]) || checkAImoves([:HYPERVOICE, :BOOMBURST]))
          end
        else
          miniscore = 0
        end
      when 0xad # Feint
        miniscore = feintcode()
      when 0xae # Mirror Move
        score = mirrorcode(false) #changes actual score so no miniscore
        score+= 10*selfstatboost([1,0,1,0,0,0,1]) if @mondata.skill >=BESTSKILL && @battle.FE == :MIRROR && score != 0
        score+= 10*selfstatboost([1,0,1,0,1,0,0]) if @mondata.skill >=BESTSKILL && @battle.FE == :SKY && score != 0
      when 0xaf # Copycat
        if @opponent.effects[:Substitute]<=0
          score = mirrorcode(true) #changes actual score so no miniscore
        else
          score=0
        end
      when 0xb0 # Me First
        miniscore = yousecondcode()
      when 0xb1 # Magic Coat
        miniscore = coatcode()
      when 0xb2 # Snatch
        miniscore = snatchcode()
      when 0xb3 # Nature Power
        #we should never need this- nature power should be changed in advance
      when 0xb4 # Sleep Talk
        miniscore = sleeptalkcode()
      when 0xb5 # Assist
        miniscore = metronomecode(25)
      when 0xb6 # Metronome
        miniscore = metronomecode(20)
        miniscore = metronomecode(40) if @battle.FE == :GLITCH
      when 0xb7 # Torment
        miniscore = tormentcode()
      when 0xb8 # Imprison
        miniscore = imprisoncode()
      when 0xb9 # Disable
        miniscore = disablecode()
      when 0xba # Taunt
        miniscore = tauntcode()
      when 0xbb # Heal Block, # Gen 9 Mod - Psychic Noise
        miniscore = healblockcode()
      when 0xbc # Encore
        miniscore = encorecode()
      when 0xbd # Double Kick, Dual Chop, Bonemerang, Double Hit, Gear Grind
        miniscore = multihitcode()
      when 0xbe # Twinneedle
        miniscore = poisoncode ** 1.2
        miniscore *= multihitcode()
      when 0xbf # Triple Kick, Triple Axel, Thunder Raid
        miniscore = multihitcode()
      when 0xc0 # Bullet Seed, Pin Missile, Arm Thrust, Bone Rush, Icicle Spear, Tail Slap, Spike Cannon, Comet Punch, Furey Swipes, Barrage, Double Slap, Fury Attack, Rock Blast, Water Shuriken
        miniscore = multihitcode()
      when 0xc1 # Beat Up
        if @opponent.index == @attacker.pbPartner.index
          score = beatupcode(initialscores[scoreindex])
        else
          miniscore = multihitcode() if @battle.pbPokemonCount(@battle.pbPartySingleOwner(@attacker.index))>0
        end
      when 0xc2 # Hyper Beam, Roar of Time, Blast Burn, Frenzy Plant, Giga Impact, Rock Wrecker, Hydro Cannon, Prismatic Laser, Meteor Assault
        miniscore = hypercode() unless @move.move == :METEORASSAULT && @battle.FE == :STARLIGHT
      when 0xc3 # Weasel Slash
        miniscore = weaselslashcode() unless @battle.FE == :CLOUDS || @battle.FE == :SKY || (Rejuv && @battle.FE == :GRASSY) || (@battle.state.effects[:GRASSY] > 0)
      when 0xc4 # Solar Beam, Solar Blade
        #if we first want to use sunny day for instant move later
        if @battle.pbWeather!=:SUNNYDAY && @attacker.pbHasMove?(:SUNNYDAY) && !(@battle.pbCheckGlobalAbility(:AIRLOCK) || @battle.pbCheckGlobalAbility(:CLOUDNINE) || @battle.pbCheckGlobalAbility(:DELTASTREAM) ||
          @battle.pbCheckGlobalAbility(:DESOLATELAND) || @battle.pbCheckGlobalAbility(:PRIMORDIALSEA) || @attacker.item == :POWERHERB || @battle.FE == :UNDERWATER || @battle.FE == :NEWWORLD || @battle.FE == :RAINBOW)
          miniscore = 0.3
        else
          miniscore = weaselslashcode() unless @battle.pbWeather == :SUNNYDAY || @battle.FE == :RAINBOW
        end
        miniscore = 0 if @battle.FE == :DARKCRYSTALCAVERN
      when 0xc5 # Freeze Shock
        miniscore = paracode()
        miniscore *= weaselslashcode() unless @battle.FE == :FROZENDIMENSION
      when 0xc6 # Ice Burn
        miniscore = burncode()
        miniscore *= weaselslashcode() unless @battle.FE == :FROZENDIMENSION
      when 0xc7 # Sky Attack
        miniscore = flinchcode()
        miniscore *= weaselslashcode() unless  @battle.FE == :CLOUDS || @battle.FE == :SKY
      when 0xc8 # Skull Bash
        miniscore = selfstatboost([0,1,0,0,0,0,0])
        miniscore *= weaselslashcode()
      when 0xc9 # Fly
        if @battle.FE == :DIMENSIONAL
          miniscore = 0 #Telling the AI that Suicide is bad hmmm kay
        elsif @attacker.ability == :NOGUARD || @opponent.ability == :NOGUARD || (@opponent.ability==:FAIRYAURA && @battle.FE == :FAIRYTALE)
          miniscore = weaselslashcode() unless @battle.FE == :CLOUDS || @battle.FE == :CAVE || @battle.FE == :SKY || (Rejuv && battle.FE == :DRAGONSDEN)
        elsif !(@battle.FE == :CLOUDS || @battle.FE == :CAVE || @battle.FE == :SKY || (Rejuv && battle.FE == :DRAGONSDEN))
          miniscore = twoturncode() unless @battle.FE == :CLOUDS || @battle.FE == :CAVE || @battle.FE == :SKY || (Rejuv && battle.FE == :DRAGONSDEN)
          miniscore*=0.3 if checkAImoves([:THUNDER,:HURRICANE])
        end
        miniscore=0 if @battle.state.effects[:Gravity]!=0
      when 0xca # Dig
        if @battle.FE == :DIMENSIONAL
          miniscore = 0 #Telling the AI that Suicide is bad hmmm kay
        elsif @attacker.ability == :NOGUARD || @opponent.ability == :NOGUARD || (@opponent.ability==:FAIRYAURA && @battle.FE == :FAIRYTALE)
          miniscore = weaselslashcode() unless (Rejuv && @battle.FE == :DESERT)
        elsif !(Rejuv && @battle.FE == :DESERT || (KAIZOMOD && @battle.FE == :ASHENBEACH))
          miniscore = twoturncode()
          miniscore*=0.3 if checkAImoves([:EARTHQUAKE])
        end
      when 0xcb # Dive
        if @battle.FE == :DIMENSIONAL
          miniscore = 0 #Telling the AI that Suicide is bad hmmm kay
        elsif @attacker.ability == :NOGUARD || @opponent.ability == :NOGUARD || (@opponent.ability==:FAIRYAURA && @battle.FE == :FAIRYTALE)
          miniscore = weaselslashcode() unless (@battle.FE == :WATERSURFACE || @battle.FE == :UNDERWATER)
        elsif !(@battle.FE == :WATERSURFACE || @battle.FE == :UNDERWATER)
          miniscore = twoturncode()
          miniscore*=0.3 if checkAImoves([:SURF])
        end
        if @battle.FE == :MURKWATERSURFACE # Murkwater Surface
          miniscore*=0.3 if !@attacker.hasType?(:POISON) && !@attacker.hasType?(:STEEL)
        end
      when 0xcc # Bounce
        if @battle.FE == :DIMENSIONAL
          miniscore = 0 #Telling the AI that Suicide is bad hmmm kay
        elsif @attacker.ability == :NOGUARD || @opponent.ability == :NOGUARD || (@opponent.ability==:FAIRYAURA && @battle.FE == :FAIRYTALE)
          miniscore = weaselslashcode() unless @battle.FE == :CLOUDS || @battle.FE == :CAVE || @battle.FE == :SKY || (Rejuv && @battle.FE == :DRAGONSDEN)
        elsif !(@battle.FE == :CLOUDS || @battle.FE == :CAVE || @battle.FE == :SKY || (Rejuv && @battle.FE == :DRAGONSDEN))
          miniscore = twoturncode()
          miniscore*= 0.3 if checkAImoves([:THUNDER,:HURRICANE])
        end
        miniscore*= paracode()
        miniscore = 0 if @battle.state.effects[:Gravity]!=0
      when 0xcd # Phantom Force, Shadow Force
        if @attacker.ability == :NOGUARD || @opponent.ability == :NOGUARD || (@opponent.ability==:FAIRYAURA && @battle.FE == :FAIRYTALE)
          miniscore = weaselslashcode() unless @battle.FE == :HAUNTED || @battle.ProgressiveFieldCheck(PBFields::DARKNESS,2,3)
        else
          miniscore = twoturncode() unless @battle.FE == :HAUNTED || @battle.ProgressiveFieldCheck(PBFields::DARKNESS,2,3)
        end
        miniscore*=1.1 if checkAImoves(PBStuff::PROTECTMOVE)
      when 0xce # Sky Drop
        if @attacker.ability == :NOGUARD || @opponent.ability == :NOGUARD || (@opponent.ability==:FAIRYAURA && @battle.FE == :FAIRYTALE)
          miniscore = weaselslashcode()
        else
          miniscore = twoturncode()
        end
        miniscore=0 if @battle.state.effects[:Gravity]!=0 || @battle.FE == :CAVE
      when 0xcf # Fire Spin, Magma Storm, Sand Tomb, Bind, Clamp, Wrap, Infestation, Thunder Cage, Snap Trap
        miniscore = firespincode()
        case @move.move
        when :FIRESPIN
          miniscore*=0.7 if @battle.FE == :ASHENBEACH
          miniscore*=1.3 if @battle.FE == :BURNING
        when :SANDTOMB
          miniscore*=1.3 if @battle.FE == :DESERT
          score+=10*oppstatdrop([0,0,0,0,0,1,0]) unless opponent.stages[PBStats::ACCURACY]<(-2) if @battle.FE == :ASHENBEACH
        when :INFESTATION
          miniscore*=1.3 if @battle.FE == :FOREST
          if @battle.FE == @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN)
            miniscore*=1.3
            miniscore*=1.3 if @battle.FE == :FLOWERGARDEN4
            miniscore*=1.5 if @battle.FE == :FLOWERGARDEN5
          end
        when :THUNDERCAGE
          miniscore*=1.3 if @battle.FE == :ELECTERRAIN
        when :SNAPTRAP
          miniscore*=1.3 if @battle.FE == :GRASSY
        end
      when 0xd0 # Whirlpool
        miniscore = firespincode()
        miniscore*=1.3 if !$cache.moves[opponent.effects[:TwoTurnAttack]].nil? &&
        $cache.moves[@opponent.effects[:TwoTurnAttack]].function==0xCB
        miniscore*=0.7 if @battle.FE == :ASHENBEACH
        if @battle.FE == :WATERSURFACE || @battle.FE == :UNDERWATER
          miniscore*=1.3
          miniscore*=confucode() if !Rejuv && opponent.effects[:Confusion]<=0
        end
        if @battle.FE == :MURKWATERSURFACE
          miniscore+=10 if miniscore==0
          miniscore*=1.5 if !(@attacker.hasType?(:POISON) || @attacker.hasType?(:STEEL))
          miniscore*=2 if !pbPartyHasType?(:POISON)
          miniscore*=2 if pbPartyHasType?(:WATER)
        end

      when 0xd1 # Uproar
        miniscore = uproarcode()
      when 0xd2 # Outrage, Petal Dance, Thrash
        miniscore*=outragecode(score)
        if @mondata.skill>=BESTSKILL
          if [:SUPERHEATED,:VOLCANICTOP].include?(@battle.FE) && @attacker.ability != :OWNTEMPO # Superheated Field
            miniscore*=0.5
          end
          if @move.move==:PETALDANCE
            miniscore*=1.5 if @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN,3,5)
          end
          if @move.move==:OUTRAGE
            miniscore*=0.8 if @battle.FE != :INVERSE && pbPartyHasType?(:FAIRY,@opponent.index)
            miniscore*=0.7 if Rejuv && @battle.FE == :CHESS && @attacker.ability != :SHELLARMOR && @attacker.ability != :BATTLEARMOR
          end
          if @move.move==:THRASH
            miniscore*=0.8 if @battle.FE != :INVERSE && pbPartyHasType?(:GHOST,@opponent.index)
            miniscore*=0.7 if Rejuv && @battle.FE == :CHESS && @attacker.ability != :SHELLARMOR && @attacker.ability != :BATTLEARMOR
          end
        end
      when 0xd3 # Rollout, Ice Ball
        miniscore = rolloutcode()
        score+=10*selfstatboost([0,0,0,0,1,0,0]) if @mondata.skill>=BESTSKILL && @battle.FE == :ICY && @move.move==:ROLLOUT
      when 0xd4 # Bide
        miniscore = bidecode()
      when 0xd5 # Recover, Heal Order, Milk Drink, Slack Off, Soft-Boiled
        recoveramount = @attacker.totalhp/2.0
        recoveramount = @attacker.totalhp*0.66 if @mondata.skill>=BESTSKILL && @move.move==:HEALORDER && @battle.FE == :FOREST # Forest
        miniscore = recovercode(recoveramount)
      when 0xd6 # Roost
        recoveramount = @attacker.totalhp/2.0
        miniscore = recovercode(recoveramount)
        bestmove=checkAIbestMove()
        if pbAIfaster?(@move) && @attacker.hasType?(:FLYING)
          if [:ROCK,:ICE,:ELECTRIC].include?(bestmove.pbType(@opponent))
            score*=1.5
          elsif [:GRASS,:BUG,:FIGHTING,:GROUND].include?(bestmove.pbType(@opponent))
            score*=0.5
          end
        end
      when 0xd7 # Wish
        miniscore = wishcode()
        miniscore*=1.2 if @mondata.skill>=BESTSKILL && (@battle.FE == :MISTY || @battle.FE == :RAINBOW || @battle.FE == :HOLY || @battle.FE == :FAIRYTALE || @battle.FE == :STARLIGHT) # Misty/Rainbow/Holy/Fairytale/Starlight
      when 0xd8 # Synthesis, Moonlight, Morning Sun
        recoveramount = (@attacker.totalhp/2.0).floor
        recoveramount = (@attacker.totalhp*0.25).floor  if @battle.pbWeather != 0 && !@attacker.hasWorkingItem(:UTILITYUMBRELLA) && @battle.pbWeather != :STRONGWINDS
        recoveramount = (@attacker.totalhp*0.66).floor  if @battle.pbWeather == :SUNNYDAY && !@attacker.hasWorkingItem(:UTILITYUMBRELLA)
        recoveramount = (@attacker.totalhp*0.125).floor if @mondata.skill>=BESTSKILL && @battle.FE == :DARKNESS3 && (@move.move==:SYNTHESIS || @move.move==:MORNINGSUN)
        recoveramount = (@attacker.totalhp*0.25).floor  if @mondata.skill>=BESTSKILL && (@battle.FE == :DARKCRYSTALCAVERN ||@battle.FE == :DARKNESS2)&& (@move.move==:SYNTHESIS || @move.move==:MORNINGSUN)
        recoveramount = (@attacker.totalhp*0.4).floor   if @mondata.skill>=BESTSKILL && @battle.FE == :DARKNESS1 && @move.move==:MOONLIGHT
        recoveramount = (@attacker.totalhp*0.75).floor  if @mondata.skill>=BESTSKILL && (([:DARKCRYSTALCAVERN,:STARLIGHT,:NEWWORLD,:BEWITCHED].include?(@battle.FE) && @move.move==:MOONLIGHT) || (Rejuv && @battle.FE == :GRASSY && @move.move == :SYNTHESIS))
        miniscore = recovercode(recoveramount)
      when 0xd9 # Rest
        miniscore = restcode()
        if @mondata.skill>=BESTSKILL
          miniscore*=1.2 if @battle.FE == :CROWD
        end
      when 0xda # Aqua Ring
        miniscore = aquaringcode()
        if @mondata.skill>=BESTSKILL
          miniscore*=1.3 if @battle.FE == :MISTY || @battle.FE == :SWAMP || @battle.FE == :WATERSURFACE || @battle.FE == :UNDERWATER
          miniscore*=1.3 if @battle.FE == :BURNING
          miniscore*=0.3 if @battle.FE == :CORROSIVEMIST
        end
      when 0xdb # Ingrain
        miniscore = aquaringcode()
        if @mondata.skill>=BESTSKILL
          if @battle.FE == :FOREST || @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN) || Rejuv && @battle.FE == :GRASSY
            miniscore*=1.3
            miniscore*=1.3 if @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN,4,5)
          end
          if @battle.FE == :SWAMP
            miniscore*=0.1 unless (@attacker.hasType?(:POISON) || @attacker.hasType?(:STEEL))
          end
          miniscore*=0.1 if @battle.FE == :CORROSIVE
        end
      when 0xdc # Leech Seed
        miniscore = leechcode()
      when 0xdd # Absorb. Leech Life, Drain Punch, Giga Drain, Horn Leech, Mega Drain, Parabolic Charge, # Gen 9 Mod - Bitter Blade
        miniscore = absorbcode(initialscores[scoreindex])
      when 0xde # Dream Eater
        miniscore = absorbcode(initialscores[scoreindex]) if @opponent.status== :SLEEP
        miniscore = 0 if @opponent.status!=:SLEEP
      when 0xdf # Heal Pulse
        miniscore = healpulsecode()
        miniscore*=1.5 if @attacker.ability == :MEGALAUNCHER
      when 0xe0 # Explosion, Self-Destruct
        miniscore = deathcode()
        score*=1.5 if @battle.FE == :GLITCH
        score*=0 if @battle.FE == :MISTY || @battle.FE == :SWAMP || @battle.pbCheckGlobalAbility(:DAMP)
      when 0xe1 # Final Gambit
        miniscore = gambitcode()
      when 0xe2 # Memento
        score = mementcode(score)
      when 0xe3 # Healing Wish
        miniscore = healwishcode()
        miniscore*=1.4 if @battle.FE == :FAIRYTALE || @battle.FE == :STARLIGHT
      when 0xe4 # Lunar Dance
        miniscore = healwishcode()
        if @battle.FE == :FAIRYTALE || @battle.FE == :STARLIGHT
          miniscore*=1.4
        elsif @battle.FE == :NEWWORLD ||  @battle.FE == :DANCEFLOOR
          miniscore*=2
        end
      when 0xe5 # Perish Song
        miniscore = perishcode()
      when 0xe6 # Grudge
        miniscore = deathcode()
        miniscore*= grudgecode()
      when 0xe7 # Destiny Bond
        miniscore = destinycode()
      when 0xe8 # Endure
        miniscore*=endurecode()
        miniscore*=0 if @battle.FE == :BURNING || @battle.FE == :MURKWATERSURFACE
      when 0xe9 # False Swipe
        miniscore = 0.1 if score>=100
      when 0xea # Teleport
        score=0
      when 0xeb # Roar, Whirlwind
        if @battle.FE == :COLOSSEUM
          miniscore = selfstatboost([2,0,0,0,0,0,0])
        else
          miniscore = phasecode()
          miniscore *= selfstatboost([2,0,0,0,0,0,0])
        end
      when 0xec # Dragon Tail, Circle Throw
        miniscore = phasecode()
      when 0xed # Baton Pass
        miniscore = pivotcode()
      when 0xee # U-turn, Volt Switch/ Gen 9 Mod - Flip Turn
        miniscore = pivotcode()
      when 0xef # Mean Look, Block, Spider Web
        miniscore = meanlookcode()
        miniscore *=1.1 if  @battle.FE == :CROWD && @move.move== :BLOCK
      when 0xf0 # Knock Off
        miniscore = knockcode()
      when 0xf1 # Covet, Thief
        miniscore = covetcode()
      when 0xf2 # Trick, Switcheroo
        miniscore = covetcode()
        miniscore *= bestowcode()
        if @battle.FE == :BACKALLEY
          if @move.move == :TRICK
            miniscore *= selfstatboost([0,0,1,0,0,0,0])
            miniscore *= oppstatdrop([0,0,1,0,0,0,0])
          elsif @move.move == :SWITCHEROO
            miniscore *= selfstatboost([1,0,0,0,0,0,0])
            miniscore *= oppstatdrop([1,0,0,0,0,0,0])
          end
        end
      when 0xf3 # Bestow
        miniscore = bestowcode()
      when 0xf4 # Bug Bite, Pluck
        miniscore = nomcode()
      when 0xf5 # Incinerate
        miniscore = roastcode()
      when 0xf6 # Recycle
        miniscore = recyclecode()
        if @battle.FE == :CITY
          subscore = selfstatboost([1,0,0,0,0,0,0]) +selfstatboost([0,1,0,0,0,0,0]) + selfstatboost([0,0,1,0,0,0,0]) +selfstatboost([0,0,0,1,0,0,0]) +selfstatboost([0,0,0,0,1,0,0])
          subscore/=5
          miniscore *= subscore
        end
      when 0xf7 # Fling
        miniscore = flingcode()
      when 0xf8 # Embargo
        miniscore = embarcode()
        miniscore *= [meanlookcode(),1].max if @battle.FE == :DIMENSIONAL
      when 0xf9 # Magic Room
        attitemscore=[embarcode(@attacker), 1].max
        miniscore = (embarcode() / attitemscore)
        miniscore*=0 if @battle.state.effects[:MagicRoom]>0
      when 0xff # Sunny Day
        miniscore=weathercode()
        miniscore*=suncode()
        if @battle.pbWeather== :RAINDANCE #Making Rainbow Field
          miniscore*= getFieldDisruptScore(@attacker,@opponent)
          miniscore*=1.2 if @attacker.hasType?(:NORMAL)
        end
        if @mondata.skill>=BESTSKILL
          miniscore*=2   if @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN) # Flower Garden
          miniscore*=2   if @battle.FE == :STARLIGHT && !pbPartyHasType?(:DARK) && !pbPartyHasType?(:FAIRY) && !pbPartyHasType?(:PSYCHIC)  # Starlight
        end
      when 0x100 # Rain Dance
        miniscore=weathercode()
        miniscore*=raincode()
        if @battle.pbWeather== :SUNNYDAY #Making Rainbow Field
          miniscore*= getFieldDisruptScore(@attacker,@opponent)
          miniscore*=1.2 if @attacker.hasType?(:NORMAL)
        end
        if !@battle.opponent.is_a?(Array)
          if Reborn && (@battle.opponent.trainertype==:SHELLY) && (@battle.FE == :GRASSY || @battle.FE == :FOREST || @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN)) # Shelly
            miniscore *= 4
            #experimental -- cancels out drop if killing moves
            miniscore*=6 if initialscores.length>0 && hasgreatmoves()
            #end experimental
          end
        end
        if @mondata.skill>=BESTSKILL
          miniscore*=1.5 if @battle.FE == :GRASSY || @battle.FE == :FOREST || @battle.FE == :SUPERHEATED # Grassy/Forest/Superheated
          miniscore*=2   if @battle.FE == :BURNING || @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN) # Burning/Flower Garden
          miniscore*=2   if @battle.FE == :STARLIGHT && !pbPartyHasType?(:DARK) && !pbPartyHasType?(:FAIRY) && !pbPartyHasType?(:PSYCHIC)  # Starlight
        end
      when 0x101 # Sandstorm
        miniscore = weathercode()
        miniscore*=sandcode()
        if @mondata.skill>=BESTSKILL
          miniscore*=1.5 if @battle.FE == :RAINBOW # Rainbow
          miniscore*=3   if @battle.FE == :BURNING # Burning
          miniscore*=2   if @battle.FE == :STARLIGHT && !pbPartyHasType?(:DARK) && !pbPartyHasType?(:FAIRY) && !pbPartyHasType?(:PSYCHIC)  # Starlight
        end
      when 0x102 # Hail
        miniscore = weathercode()
        miniscore*=hailcode()
        if @mondata.skill>=BESTSKILL
          miniscore*=1.5 if @battle.FE == :RAINBOW || @battle.FE == :MOUNTAIN # Rainbow/Mountain
          miniscore*=2   if @battle.FE == :STARLIGHT && !pbPartyHasType?(:DARK) && !pbPartyHasType?(:FAIRY) && !pbPartyHasType?(:PSYCHIC)  # Starlight
        end
      when 0x103 # Spikes
        if @attacker.pbOpposingSide.effects[:Spikes] < 3
          miniscore = hazardcode()
          miniscore*=0.9 if @attacker.pbOpposingSide.effects[:Spikes]>0
          if @mondata.skill>=BESTSKILL
            miniscore*=0 if @battle.FE == :WATERSURFACE || @battle.FE == :MURKWATERSURFACE # (Murk)Water Surface
            miniscore*=1.3 if Rejuv && @battle.FE == :ELECTERRAIN
          end
        else
          miniscore*=0
        end
        if @mondata.skill>=BESTSKILL
          if @battle.FE == :WASTELAND # Wasteland
            miniscore = 1
            score = ((@opponent.totalhp/3.0)/@opponent.hp)*100
            score*=1.5 if @battle.doublebattle
          end
        end
      when 0x104 # Toxic Spikes
        if @attacker.pbOpposingSide.effects[:ToxicSpikes] < 2
          miniscore = hazardcode()
          miniscore*=0.9 if @attacker.pbOpposingSide.effects[:ToxicSpikes]>0
          if @mondata.skill>=BESTSKILL
            miniscore*=0 if @battle.FE == :WATERSURFACE || @battle.FE == :MURKWATERSURFACE # (Murk)Water Surface
            miniscore*=1.2 if @battle.FE == :CORROSIVE # Corrosive
          end
        else
          miniscore*=0
        end
        if @mondata.skill>=BESTSKILL
          if @battle.FE == :WASTELAND && !@opponent.isAirborne? # Wasteland
            miniscore = 1
            score = [((@opponent.totalhp*0.13)/@opponent.hp)*100, 110].min
            score*= @opponent.pbCanPoison?(false) ? 1.5 : 0
            score*= 0.6 if hasgreatmoves()
            score*=1.5 if @battle.doublebattle
            score*=0 if @opponent.hasType?(:POISON)
          elsif @battle.FE == :WASTELAND && @opponent.isAirborne?
            score=0
          end
        end
      when 0x105 # Stealth Rocks
        if !@attacker.pbOpposingSide.effects[:StealthRock]
          miniscore = hazardcode()
          miniscore*=1.05 if @attacker.moves.any? {|moveloop| moveloop!=nil && (moveloop.move==:SPIKES || moveloop.move==:TOXICSPIKES)}
          if @mondata.skill>=BESTSKILL
            miniscore*=2 if @battle.FE == :CAVE || @battle.FE == :ROCKY # Cave/Rocky
            miniscore*=1.3 if @battle.FE == :CRYSTALCAVERN # Crystal Cavern
            miniscore*=1.3 if Rejuv && (@battle.FE == :CORRUPTED) # Poison rock fields
            miniscore*=1.3 if Rejuv && (@battle.FE == :DRAGONSDEN || @battle.FE == :VOLCANICTOP || @battle.FE == :INFERNAL) # fire rock fields
          end
        else
          miniscore=0
        end
        if @mondata.skill>=BESTSKILL
          if @battle.FE == :WASTELAND && !(@opponent.ability==:MAGICBOUNCE || @opponent.pbPartner.ability==:MAGICBOUNCE) &&
            (@opponent.effects[:MagicCoat]==true || @opponent.pbPartner.effects[:MagicCoat]==true) # Wasteland
            miniscore=1.0
            score = ((@opponent.totalhp/4.0)/@opponent.hp)*100
            score*=2 if pbTypeModNoMessages(:ROCK,@attacker,@opponent,@move,@mondata.skill)>4
            score*=1.5 if @battle.doublebattle
          end
        end
      when 0x106 # Grass Pledge
        miniscore*= 1.5 if @attacker.pbPartner.pbHasMove?(:FIREPLEDGE) || @attacker.pbPartner.pbHasMove?(:WATERPLEDGE)
        if @battle.field.checkPledge(:GRASSPLEDGE)
          miniscore = getFieldDisruptScore(@attacker,@opponent)
          case @battle.field.pledge
            when :WATERPLEDGE then miniscore/= getFieldDisruptScore(@attacker,@opponent,:SWAMP)
            when :FIREPLEDGE then miniscore/=getFieldDisruptScore(@attacker,@opponent,:BURNING)
          end
        end
      when 0x107 # Fire Pledge
        miniscore*= 1.5 if @attacker.pbPartner.pbHasMove?(:GRASSPLEDGE) || @attacker.pbPartner.pbHasMove?(:WATERPLEDGE)
        if @battle.field.checkPledge(:FIREPLEDGE)
          miniscore = getFieldDisruptScore(@attacker,@opponent)
          case @battle.field.pledge
            when :WATERPLEDGE then miniscore/= getFieldDisruptScore(@attacker,@opponent,:RAINBOW)
            when :GRASSPLEDGE then miniscore/=getFieldDisruptScore(@attacker,@opponent,:BURNING)
          end
        end
      when 0x108 # Water Pledge
        miniscore*= 1.5 if @attacker.pbPartner.pbHasMove?(:FIREPLEDGE) || @attacker.pbPartner.pbHasMove?(:GRASSPLEDGE)
        if @battle.field.checkPledge(:WATERPLEDGE)
          miniscore = getFieldDisruptScore(@attacker,@opponent)
          case @battle.field.pledge
            when :GRASSPLEDGE then miniscore/= getFieldDisruptScore(@attacker,@opponent,:SWAMP)
            when :FIREPLEDGE then miniscore/=getFieldDisruptScore(@attacker,@opponent,:RAINBOW)
          end
        end
      when 0x10a # Brick Break, Psychic Fangs
        miniscore = brickbreakcode()
      when 0x10b # Hi Jump Kick, Jump Kick, # Gen 9 Mod - Supercell Slam
        miniscore = jumpcode(score)
        if @attacker.index != 2 && @mondata.skill>=BESTSKILL
          miniscore*= 0.5 if @battle.FE != :INVERSE && pbPartyHasType?(:GHOST, @opponent.index) && (@move.move == :HIJUMPKICK || @move.move == :JUMPKICK)
          miniscore*= 0.5 if @battle.FE != :INVERSE && pbPartyHasType?(:GROUND, @opponent.index) && @move.move == :SUPERCELLSLAM
        end
      when 0x10c # Substitute
        miniscore=subcode()
      when 0x10d # Curse
        if @attacker.hasType?(:GHOST)
          miniscore = spoopycode()
          miniscore = 0 if @battle.FE == :HOLY
        else
          miniscore = selfstatboost([1,1,0,0,0,0,0])
          miniscore *= selfstatdrop([0,0,0,0,1,0,0],score)
        end
      when 0x10e # Spite
        score=spitecode(score)
      when 0x10f # Nightmare
        miniscore = nightmarecode()
        miniscore*=0 if @battle.FE == :RAINBOW
      when 0x110 # Rapid Spin, # Gen 9 Mod - Mortal Spin
        score+=20 if @attacker.effects[:LeechSeed]>=0
        score+=10 if @attacker.effects[:MultiTurn]>0
        if @attacker.pbNonActivePokemonCount>0
          score+=25 if @attacker.pbOwnSide.effects[:StealthRock]
          score+=25 if @attacker.pbOwnSide.effects[:StickyWeb]
          score+= (10*@attacker.pbOwnSide.effects[:Spikes])
          score+= (15*@attacker.pbOwnSide.effects[:ToxicSpikes])
        end
        # Gen 9 Mod - Added poisoncode for mortal spin.
        if @move.move == :MORTALSPIN
          score*=poisoncode()
        end
      when 0x111 # Future Sight, Doom Desire
        miniscore = futurecode()
      when 0x112 # Stockpile
        if @attacker.effects[:Stockpile]<3
          miniscore = selfstatboost([1,1,0,0,0,0,0])
        else
          miniscore = 0
        end
      when 0x113 # Spit Up
        if @attacker.effects[:Stockpile]==0
          miniscore=0
        else
          miniscore=antistatcode([0,@attacker.effects[:Stockpile],0,0,@attacker.effects[:Stockpile],0,0],score)
          if @attacker.pbHasMove?(:SWALLOW) && @attacker.hp/(@attacker.totalhp.to_f) < 0.66
            miniscore*=0.8
            miniscore*=0.5 if @attacker.hp < 0.4*@attacker.totalhp
          end
        end
      when 0x114 # Swallow
        if @attacker.effects[:Stockpile]==0
          miniscore=0
        else
          miniscore = recovercode()
          miniscore*=selfstatdrop([0,@attacker.effects[:Stockpile],0,0,@attacker.effects[:Stockpile],0,0],score)
        end
      when 0x115 # Focus Punch
        miniscore = focuscode()
      when 0x116 # Sucker Punch, # Gen 9 Mod - Thunderclap
        miniscore = suckercode()
      when 0x117 # Follow Me, Rage Powder
        miniscore = followcode()
      when 0x118 # Gravity
        if @battle.FE != :DEEPEARTH
          miniscore = gravicode()
          if @battle.state.effects[:Gravity]==0 && @mondata.skill>=BESTSKILL
            if @battle.FE == :NEWWORLD
              score*=2 if !@attacker.hasType?(:FLYING) && ![:LEVITATE,:SOLARDIOL,:LUNARIDOL].include?(@attacker.ability)
              score*=2 if @opponent.hasType?(:FLYING) || [:LEVITATE,:SOLARDIOL,:LUNARIDOL].include?(@opponent.ability)
              if pbPartyHasType?(:PSYCHIC) || pbPartyHasType?(:FAIRY) || pbPartyHasType?(:DARK)
                score*=2
                score*=2 if @attacker.hasType?(:PSYCHIC) || @attacker.hasType?(:FAIRY) || @attacker.hasType?(:DARK)
              end
            end
          end
        end
      when 0x119 # Magnet Rise
        miniscore = magnocode()
        miniscore*=1.3 if @mondata.skill>=BESTSKILL && (@battle.FE == :ELECTERRAIN || @battle.FE == :FACTORY || @battle.FE == :SHORTCIRCUIT || @battle.state.effects[:ELECTERRAIN] > 0)
      when 0x11a # Telekineis
        score = telecode()
      #when 0x11b # Sky Uppercut
      when 0x11c # Smack Down, Thousand Arrows
        miniscore = smackcode()
      when 0x11d # After You
        miniscore = afteryoucode()
        if @battle.opponent.is_a?(Array) && @battle.opponent.any? {|opp| opp.trainertype == :UMBNOEL } &&
          @battle.turncount == 1 && @opponent.index == @attacker.pbPartner.index
          score += 150
        end
      when 0x11e # Quash
        #we could technically have _some_ code for this
      when 0x11f # Trick Room
        miniscore = trcode()
        if @mondata.skill>=BESTSKILL
          miniscore*=1.5 if @battle.FE == :CHESS || @battle.FE == :NEWWORLD || @battle.FE == :PSYTERRAIN || (Rejuv && @battle.FE == :STARLIGHT) # Chess/New World/Psychic Terrain
        end
      when 0x120 # Ally Switch
        miniscore = dinglenugget()
      #when 0x121 # Foul Play
      #when 0x122 # Secret Sword, Psystrike, Psyshock
      when 0x123 # Synchronoise
        score=0 if !@opponent.hasType?(@attacker.type1) && (!@opponent.hasType?(@attacker.type2) || @attacker.type2.nil?)
      when 0x124 # Wonder Room
        miniscore = wondercode()
      when 0x125 # Last Resort
        miniscore = lastcode()
      when 0x126 # Shadow moves (basic)
        score*=1.2
      when 0x127 # Shadow Bolt
        miniscore = 1.2*paracode()
      when 0x128 # Shadow Fire
        miniscore = 1.2*burncode()
      when 0x129 # Shadow Chill
        miniscore = 1.2* (KAIZOMOD ? frostbitecode() : freezecode())
      when 0x12a # Shadow Panic
        miniscore = 1.2*confucode()
      when 0x132 # Shadow Shed (like a hut or a tool shed, i presume.)
        miniscore = brickbreakcode() / brickbreakcode(@opponent)
      when 0x133 # King's Shield
        miniscore = protecteffectcode()
        if !pbAIfaster?() && @attacker.species == :AEGISLASH && @attacker.form==1
          score*=4
          #experimental -- cancels out drop if killing moves
          score*=6 if initialscores.length>0 && hasgreatmoves()
        end
      when 0x134 # Electric Terrain
        miniscore = electricterraincode()
      when 0x135 # Grassy Terrain
        miniscore = grassyterraincode()
      when 0x136 # Misty Terrain
        miniscore = mistyterraincode()
      when 0x137 # Flying Press
        #score*=2 if opponent.effects[:Minimize] #handled in pbRoughDamage from now on
        miniscore = 0 if @battle.state.effects[:Gravity]!=0
      when 0x138 # Noble Roar, Tearful Look
        statarray = [1,0,1,0,0,0,0]
        statarray = [2,0,2,0,0,0,0] if @move.move==:NOBLEROAR && @mondata.skill >=BESTSKILL && (@battle.FE == :FAIRYTALE || @battle.FE == :DRAGONSDEN)
        miniscore=oppstatdrop(statarray)
      when 0x139 # Draining Kiss, Oblivion Wing
        miniscore=absorbcode(initialscores[scoreindex])
      when 0x13a # Aromatic Mist
        miniscore=arocode(PBStats::SPDEF)
      when 0x13b # Eerie Impulse
        statarray = [0,0,2,0,0,0,0]
        statarray = [0,0,3,0,0,0,0] if @mondata.skill >=BESTSKILL && @battle.FE == :ELECTERRAIN
        miniscore = oppstatdrop(statarray)
      when 0x13c # Belch
        miniscore=0 if !@attacker.pokemon.belch && @attacker.crested != :SWALOT
      when 0x13d # Parting Shot
        miniscore = pivotcode()
        statarray = [1,0,1,0,0,0,0]
        statarray = [1,0,1,0,1,0,0] if @mondata.skill >=BESTSKILL && @battle.FE == :FROZENDIMENSION
        statarray = [2,0,2,0,0,0,0] if @mondata.skill >=BESTSKILL && (@battle.ProgressiveFieldCheck(PBFields::CONCERT) || @battle.FE == :BACKALLEY)
        miniscore*=oppstatdrop(statarray)
      when 0x13e # Geomancy
        miniscore = weaselslashcode() if !(@mondata.skill>=BESTSKILL && @battle.FE == :STARLIGHT)
        miniscore *= selfstatboost([0,0,2,2,2,0,0])
        if @battle.FE == :NEWWORLD
          miniscore*=2 if !@attacker.isAirborne?
          miniscore*=2 if @opponent.isAirborne?
          if pbPartyHasType?(:PSYCHIC) || pbPartyHasType?(:FAIRY) || pbPartyHasType?(:DARK)
            miniscore*=2
            miniscore*=2 if @attacker.hasType?(:PSYCHIC) || @attacker.hasType?(:FAIRY) || @attacker.hasType?(:DARK)
          end
        end
      when 0x13f # Venom Drench
        if @opponent.status== :POISON || @battle.FE == :CORROSIVE || @battle.FE == :CORROSIVEMIST || @battle.FE == :WASTELAND || @battle.FE == :MURKWATERSURFACE
          miniscore = oppstatdrop([1,0,1,0,1,0,0])
        else
          miniscore = 0
        end
      when 0x140 # Spiky Shield
        miniscore = protecteffectcode()
      when 0x141 # Sticky Web
        if @battle.FE != :WASTELAND # Wasteland
          if !@attacker.pbOpposingSide.effects[:StickyWeb]
            miniscore = hazardcode
            miniscore*= 2 if @battle.FE == :FOREST && @mondata.skill>=BESTSKILL
          else
            miniscore = 0
          end
        else
          miniscore=oppstatdrop([0,0,0,0,1,0,0])
        end
      when 0x142 # Topsy Turvy
        miniscore = turvycode()
        if !Rejuv && @battle.canChangeFE?(:INVERSE)
          for type in [@opponent.type1,@opponent.type2]
            effcheck = PBTypes.twoTypeEff(type,@attacker.type1,@attacker.type2)
            score*=2 if effcheck>4
            score*=0.5 if effcheck!=0 && effcheck<4
            score*=0.1 if effcheck==0
          end
          for type in [@attacker.type1, @attacker.type2]
            effcheck = PBTypes.twoTypeEff(type,@opponent.type1,@opponent.type2)
            score*=0.5 if effcheck>4
            score*=2 if effcheck!=0 && effcheck<4
            score*=3 if effcheck==0
          end
        end
      when 0x143 # Forest's Curse
        miniscore = opptypechangecode(:GRASS)
        miniscore *= spoopycode() if @battle.FE == :FOREST || @battle.FE == :FAIRYTALE || @battle.FE == :BEWITCHED
      when 0x144 # Trick or Treat
        miniscore = opptypechangecode(:GHOST)
      when 0x145 # Fairy Lock
        miniscore = fairylockcode()
      when 0x146 # Magnetic Flux
        if !(@attacker.ability == :PLUS || @attacker.ability == :MINUS || @attacker.pbPartner.ability == :PLUS || @attacker.pbPartner.ability == :MINUS)
          if Rejuv && @battle.FE == :ELECTERRAIN
            miniscore = selfstatboost([0,1,0,1,0,0,0])
          else
            miniscore=0
          end
        elsif @attacker.ability == :PLUS || @attacker.ability == :MINUS
          miniscore = selfstatboost([0,1,0,1,0,0,0])
          miniscore = selfstatboost([0,2,0,2,0,0,0]) if Rejuv && @battle.FE == :ELECTERRAIN
        elsif @attacker.pbPartner.stages[PBStats::SPDEF]!=6 && @attacker.pbPartner.stages[PBStats::DEFENSE]!=6
          miniscore=0.7
          miniscore*=1.3 if initialscores.length>0 && hasbadmoves(20)
          miniscore*=1.1 if @attacker.pbPartner.hp>@attacker.pbPartner.totalhp*0.75
          miniscore*=0.3 if @attacker.pbPartner.effects[:Yawn]>0 || @attacker.pbPartner.effects[:LeechSeed]>=0 || @attacker.pbPartner.effects[:Attract]>=0 || !@attacker.pbPartner.status.nil?
          miniscore*=0.3 if checkAImoves(PBStuff::PHASEMOVE)
          miniscore*=0.5 if @opponent.ability == :UNAWARE
          miniscore*=1.2 if hpGainPerTurn(@attacker.pbPartner)>1
        end
      when 0x147 # Fell Stinger
        if @attacker.stages[PBStats::ATTACK]!=6 && score>=100
          miniscore = 2.0
          miniscore*=2 if pbAIfaster?(@move)
        end
      when 0x148 # Ion Deluge
        miniscore = electricterraincode()
        miniscore*= moveturnselectriccode(false,false)

      when 0x149 # Crafty Shield
        score = craftyshieldcode(score)

      when 0x150 # Flower Shield
        miniscore = arocode(PBStats::DEFENSE)
        score = flowershieldcode(score)

      when 0x151 # Rototiller
        miniscore = arocode(PBStats::ATTACK)
        score = rotocode(score)
      when 0x152 # Powder
        miniscore = powdercode()
      when 0x153 # Electrify
        miniscore = moveturnselectriccode(true,false)
        miniscore *= [opptypechangecode(:ELECTRIC),1].max if Rejuv && @battle.FE == :ELECTERRAIN
      when 0x154 # Mat Block
        if @attacker.turncount==0 && (pbAIfaster?() || pbAIfaster?(nil,nil,@attacker,@opponent.pbPartner))
          miniscore = protectcode()
          miniscore *= 1.3 if @battle.doublebattle
        else
          miniscore = 0
        end
      when 0x155 # Thousand Waves, Anchor Shot, Spirit Shackle
        miniscore = meanlookcode()
      when 0x157 # Hyperspace Hole
        miniscore = nevermisscode(initialscores[scoreindex])
        miniscore*=feintcode()
      when 0x159 # Hyperspace Fury
        if @attacker.species==:HOOPA && @attacker.form==1 # Hoopa-U
          miniscore = nevermisscode(initialscores[scoreindex])
          miniscore*=feintcode()
          if @attacker.ability == :CONTRARY
            miniscore *= selfstatboost([0,1,0,0,0,0,0])
          else
            miniscore*=selfstatdrop([0,1,0,0,0],score)
          end
        else
          score = 0
        end
      when 0x15b # Aurora Veil
        miniscore = screencode()
        miniscore*=1.5 if @mondata.skill>=BESTSKILL && @battle.FE == :MIRROR # Mirror
      when 0x15c # Baneful Bunker
        miniscore = protecteffectcode()
        if !@opponent.status.nil?
          miniscore*=0.8
        elsif @opponent.pbCanPoison?(false)
          miniscore*=1.3
          miniscore*=1.3 if @attacker.ability == :MERCILESS
          miniscore*=1.3 if @attacker.crested == :ARIADOS
          miniscore*=0.3 if @opponent.ability == :POISONHEAL
          miniscore*=0.3 if @opponent.crested == :ZANGOOSE
          miniscore*=0.7 if @opponent.ability == :TOXICBOOST
        end
      when 0x15d # Beak Blast
        miniscore = beakcode()
      when 0x15e # Burn Up
        miniscore = burnupcode()
      when 0x15f # Clanging Scales
        if @attacker.ability == :CONTRARY
          miniscore = selfstatboost([0,1,0,0,0,0,0])
        else
          miniscore = antistatcode([0,1,0,0,0],initialscores[scoreindex])
        end
      when 0x160 # Core Enforcer
        if !(PBStuff::FIXEDABILITIES).include?(@opponent.ability) && !@opponent.effects[:GastroAcid] && @opponent.effects[:Substitute]<=0
          miniscore = getAbilityDisruptScore(@attacker,@opponent)
          # Gen 9 Mod - Added Ability Shield
          miniscore = 1 if (@mondata.oppitemworks && @opponent.item == :ABILITYSHIELD)
          miniscore*=1.3 if !pbAIfaster?(@move)
          miniscore*=1.3 if checkAIpriority()
          score*=miniscore if !pbAIfaster?(@move) || checkAIpriority()
          end
      when 0x161 # First Impression
        score=0 if @attacker.turncount!=0
        miniscore = (score>=110) ? 1.1 : 1.0
        miniscore*=feintcode() if @battle.FE == :COLOSSEUM
      when 0x162 # Floral Healing
        miniscore = healpulsecode()
        miniscore*=1.5 if @battle.FE == :GRASSY || @battle.FE == :FAIRYTALE || @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN,3,5)
        miniscore*=0.2 if @attacker.status!=:POISON && (@battle.FE == :CORROSIVE || @battle.FE == :CORROSIVEMIST)
      when 0x163 # Gear Up
        if !(@attacker.ability == :PLUS || @attacker.ability == :MINUS || @attacker.pbPartner.ability == :PLUS || attacker.pbPartner.ability == :MINUS)
          miniscore=0
        elsif @attacker.ability == :PLUS || @attacker.ability == :MINUS
          miniscore = selfstatboost([1,0,0,1,0,0,0])
        else
          miniscore=1.0
          miniscore*=1.3 if initialscores.length>0 && hasbadmoves(20)
          miniscore*=1.1 if @attacker.pbPartner.hp>@attacker.pbPartner.totalhp*0.75
          miniscore*=0.3 if @attacker.pbPartner.effects[:Yawn]>0 || @attacker.pbPartner.effects[:LeechSeed]>=0 || @attacker.pbPartner.effects[:Attract]>=0 || !@attacker.pbPartner.status.nil?
          miniscore*=0.3 if checkAImoves(PBStuff::PHASEMOVE)
          miniscore*=0.5 if @opponent.ability == :UNAWARE
        end
      when 0x164 # Instruct
        if !@battle.doublebattle || @opponent.index!=@attacker.pbPartner.index || !@opponent.lastMoveUsedSketch.is_a?(Symbol)
          score=1
        else
          score*=instructcode()
          score=1 if @attacker.pbPartner.hp==0
        end
      when 0x165 # Laser Focus
        miniscore = permacritcode(initialscores[scoreindex])
      when 0x166 # Moongeist Beam, Sun Steel Strike
        miniscore = moldbreakeronalaser()
      when 0x167 # Pollen Puff
        if @opponent.index==@attacker.pbPartner.index
          score=15*healpulsecode()
          score=0 if @opponent.ability == :BULLETPROOF
        end
      when 0x168 # Psychic Terrain
        miniscore = psychicterraincode()
      when 0x169 # Purify
        miniscore = almostuselessmovecode()
      when 0x16b # Shell Trap
        miniscore = shelltrapcode()
      when 0x16c # Shore Up
        recoveramount = @attacker.totalhp/2.0
        recoveramount = @attacker.totalhp if @mondata.skill >= BESTSKILL && @battle.FE == :ASHENBEACH
        recoveramount = @attacker.totalhp*0.66 if @battle.pbWeather== :SANDSTORM || @mondata.skill >= BESTSKILL && @battle.FE == :DESERT
        miniscore = recovercode(recoveramount)
        miniscore*= selfstatboost([0,2,0,0,0,0,0]) if @attacker.ability ==:WATERCOMPACTION && @mondata.skill >= BESTSKILL && (@battle.FE == :WATERSURFACE || @battle.FE == :MURKWATERSURFACE)
      when 0x16d # Sparkling Aria
        miniscore = (@opponent.status== :BURN && @opponent.ability != :SHIELDDUST && @opponent.item != :COVERTCLOAK) ? 0.6 : 1.0
      when 0x16e # Spectral Thief
        miniscore = spectralthiefcode()
      when 0x16f # Speed Swap
        miniscore=stupidmovecode()
      when 0x170 # Spotlight
        miniscore = spotlightcode()
      when 0x171 # Stomping Tantrum, # Gen 9 Mod - Temper Flare
        miniscore = 1.0
        miniscore*=0.8 if Rejuv && @battle.FE == :CHESS && @attacker.ability != :SHELLARMOR && @attacker.ability != :BATTLEARMOR && @move.move == :STOMPINGTANTRUM
      when 0x172 # Strength Sap
        miniscore = recovercode()
        statarray = [1,0,0,0,0,0,0]
        statarray = [1,0,1,0,0,0,0] if @battle.FE == :BEWITCHED
        miniscore*=oppstatdrop(statarray)
      when 0x173 # Throat Chop
        miniscore = chopcode()
      when 0x174 # Toxic Thread
        miniscore = poisoncode()
        miniscore*=oppstatdrop([0,0,0,0,1,0,0])
      when 0x175 # Mind Blown/Steel beam
        miniscore = pussydeathcode(initialscores[scoreindex])
        miniscore = deathcode() if @battle.FE == :SHORTCIRCUIT && @move.move == :STEELBEAM
        if (@battle.FE == :MISTY || @battle.FE == :SWAMP) && @move.move == :MINDBLOWN
          miniscore*=0
        end
      when 0x176 # Photon Geyser
        miniscore = moldbreakeronalaser()
      when 0x177 # Plasma Fists
        miniscore = electricterraincode()
        miniscore*= moveturnselectriccode(false,true)
      when 0x179 # Snipe Shot
        if @battle.doublebattle
          if checkAImoves([:FOLLOWME,:RAGEPOWDER],getAIMemory(@opponent.pbPartner)) || checkAImoves([:SPOTLIGHT]) || [:STORMDRAIN,:LIGHTNINGROD].include?(@opponent.pbPartner.ability)
            miniscore=1.2
          end
        end
      when 0x17A # Stuff Cheeks
        if pbIsBerry?(@attacker.item)
          miniscore = selfstatboost([0,2,0,0,0,0,0])
          case @attacker.item
          when :LUMBERRY then miniscore*=2 if !@attacker.status.nil?
          when :CHERIBERRY then miniscore*=2 if @attacker.status == :PARALYSIS
          when :RAWSTBERRY then miniscore*=2 if @attacker.status == :BURN
          when :PECHABERRY then miniscore*=2 if @attacker.status == :POISON
          when :SITRUSBERRY, :FIGYBERRY, :WIKIBERRY, :MAGOBERRY, :AGUAVBERRY, :IAPAPABERRY then miniscore*=1.6 if @attacker.hp*(1.0/@attacker.totalhp)<0.66
          when :LIECHIBERRY then miniscore*=1.5 if @attacker.attack>@attacker.spatk
          when :PETAYABERRY then miniscore*=1.5 if @attacker.spatk>@attacker.attack
          when :APICOTBERRY,:GANLONBERRY,:STARFBERRY then miniscore*=1.5
          when :CUSTAPBERRY, :SALACBERRY then miniscore*= pbAIfaster? ? 1.1 : 1.5
          end
        else
          score*=0
        end
      when 0x17B # No Retreat
        if !@attacker.effects[:NoRetreat]
          statarray = [1,1,1,1,1,0,0]
          statarray = [2,0,2,0,2,0,0]  if @battle.FE == :CHESS
          statarray = [2,2,2,2,2,0,0]   if @battle.FE == :COLOSSEUM
          miniscore = selfstatboost(statarray)
          if @battle.FE == :CHESS
            miniscore*= selfstatdrop([0,1,0,1,0,0,0],score) if (@mondata.attitemworks && @attacker.item != :WHITEHERB)
            if (@mondata.attitemworks && @attacker.item == :WHITEHERB)
              miniscore*=1.3
            else
              miniscore*=0.8
            end
          end
        else
          score*=0
        end
      when 0x17C # Tar Shot
        miniscore=oppstatdrop([0,0,0,0,1,0,0])
        if !@opponent.effects[:TarShot] && (PBTypes.twoTypeEff(:FIRE,@opponent.type1,@opponent.type2) != 0) && @opponent.ability != :FLASHFIRE
          if pbPartyHasType?(:FIRE)
            miniscore*=1.2 unless @battle.FE == :WATERSURFACE
          end
          miniscore*=1.2 if @battle.FE == :VOLCANIC || @battle.FE == :VOLCANICTOP
        end
        if @battle.FE == :MURKWATERSURFACE || @battle.FE == :CORRUPTED
          sidescore=poisoncode()
          miniscore*=sidescore if sidescore > 1
        end
      when 0x17D # Magic Powder
        miniscore = opptypechangecode(:PSYCHIC)
        miniscore*=[sleepcode(),1].max if @battle.FE == :HAUNTED || @battle.FE == :BEWITCHED
      when 0x17E # Dragon Darts
        if !@battle.doublebattle || @move.pbDragonDartTargetting(@attacker).length < 2
          miniscore = multihitcode()
        else
          miniscore = 1.2 if checkAImoves(PBStuff::PROTECTMOVE) || pbPartyHasType?(:FAIRY) # @SWu idk
        end
      when 0x17F # teatime
        miniscore = teaslurpcode()
      when 0x180 # Octolock
        miniscore = firespincode()
        miniscore*= oppstatdrop([0,1,0,1,0,0,0])
      when 0x182 # Court Change
        miniscore = defogcode()
      when 0x183 # Clangorous Soul
        statarray = [1,1,1,1,1,0,0]
        statarray = [2,2,2,2,2,0,0] if @mondata.skill >= BESTSKILL && [:BIGTOP,:CONCERT1,:CONCERT2,:CONCERT3,:CONCERT4].include?(@battle.FE)
        miniscore = selfstatboost(statarray) ** 1.2 #More extreme scoring
        miniscore *= 0.3 if !@attacker.moves.any?{|moveloop| moveloop!=nil && moveloop.basedamage > 0 && moveloop.pbIsPriorityMoveAI(@attacker)} && !pbAIfaster?()
        miniscore *= 1.2 if @attacker.turncount<1
        miniscore = 1 if (@attacker.hp.to_f)/@attacker.totalhp <= 0.333 || ((@mondata.skill >= BESTSKILL && [:BIGTOP,:CONCERT1,:CONCERT2,:CONCERT3,:CONCERT4].include?(@battle.FE)) && (@attacker.hp.to_f)/@attacker.totalhp <= 0.5)
      when 0x185 # Decorate
        if @opponent.ability == :CONTRARY
          miniscore = oppstatdrop([2, 0, 2, 0, 0, 0, 0])
        else
          miniscore = oppstatboost([2, 0, 2, 0, 0])
        end
      when 0x186 # Aura Wheel
        miniscore = selfstatboost([0,0,0,0,1,0,0])
      when 0x187 # Life Dew
        recoveramount = @attacker.totalhp/4.0
        recoveramount = @attacker.totalhp/2.0 if @mondata.skill>=BESTSKILL && (@battle.FE == :RAINBOW || @battle.FE == :HOLY)
        miniscore = lifedewcode(recoveramount)
        miniscore *= 0.5 if @battle.FE == :CORROSIVEMIST && !@attacker.hasType?(:POISON) && !@attacker.hasType?(:STEEL) # self poisoning (provisonal, kind of a complex topic would like to invert poisoncode)
        miniscore *= aquaringcode() if @battle.FE == :WATERSURFACE
      when 0x188 # Obstruct
        miniscore = protecteffectcode()
      when 0x189 # Jaw Lock
        miniscore = meanlookcode()
      when 0x306 # Steel Roller, # Gen 9 Mod - Ice Spinner
        miniscore = getFieldDisruptScore(@attacker,@opponent)
        miniscore = 0 if @battle.FE == :INDOOR && @move.move == :STEELROLLER
      when 0x307 # Scale Shot
        miniscore = multihitcode()
        miniscore *= selfstatboost([0,0,0,0,1,0,0])
        miniscore *= selfstatdrop([0,1,0,0,0,0,0],score)
      when 0x308 # Meteor Beam
        miniscore = selfstatboost([0,0,1,0,0,0,0])
        miniscore *= weaselslashcode() unless @battle.FE == :STARLIGHT || @battle.FE == :NEWWORLD
      when 0x309 # Shell Side Arm
        miniscore = poisoncode()
      when 0x313 # Burning Jealousy, # Gen 9 Mod - Alluring Voice
        miniscore = burncode() if ((checkAImoves(PBStuff::SETUPMOVE) && !pbAIfaster?()) || @opponent.effects[:Jealousy]) && @move.move == :BURNINGJEALOUSY
        miniscore = confucode() if ((checkAImoves(PBStuff::SETUPMOVE) && !pbAIfaster?()) || @opponent.effects[:Jealousy]) && @move.move == :ALLURINGVOICE
      when 0x314 # Lash Out
        miniscore = 1.5 if (checkAImoves(PBStuff::STATNERFMOVE) && !pbAIfaster?()) && !@attacker.effects[:LashOut]
        # score is already higher from damage if lashout condition is fulfilled when turn starts (via intimidate etc)
      when 0x315 # Poltergeist
        miniscore = 0 if @opponent.item.nil?
      when 0x316 # Corrosive Gas
        miniscore = knockcode()
        miniscore *= oppstatdrop([1,1,1,1,1,0,0]) if [:BACKALLEY,:CITY].include?(@battle.FE)
      when 0x317 # Coaching
        if @opponent.index == @attacker.pbPartner.index
          if @opponent.ability == :CONTRARY
            miniscore = oppstatdrop([1, 1, 0, 0, 0, 0, 0])
          else
            miniscore = oppstatboost([1, 1, 0, 0, 0])
          end
        else
          miniscore = 0
        end
      when 0x318 # Jungle Healing
        recoveramount = @attacker.totalhp/4.0
        miniscore = lifedewcode(recoveramount)
      when 0x319 # Surging Strikes
        miniscore = permacritcode(initialscores[scoreindex])
        miniscore *= multihitcode()
      when 0x320 # Eerie Spell
        miniscore = spitecode(score)
      # PLA moves
      when 0x500 # Dire Claw
        miniscore = (sleepcode() + poisoncode() + paracode()) / 3
      when 0x501 # Victory Dance
        statarray = [1,1,0,0,1,0,0]
        statarray = [2,2,0,0,2,0,0] if @mondata.skill >= BESTSKILL && (@battle.FE == :BIGTOP || @battle.FE == :DANCEFLOOR)
        miniscore = selfstatboost(statarray)
      when 0x502 # Barb Barrage
        miniscore = poisoncode()
      when 0x503 # Triple Arrows
        miniscore = oppstatdrop([0,1,0,0,0,0,0])
        miniscore *= flinchcode()
      when 0x504 # Infernal Parade
        miniscore = burncode()
      when 0x505 # Take Heart
        statarray = [0,0,1,1,0,0,0]
        statarray = [0,0,2,2,0,0,0] if @mondata.skill >= BESTSKILL && (@battle.FE == :WATERSURFACE || @battle.FE == :UNDERWATER)
        miniscore = selfstatboost(statarray)
        miniscore *= [refreshcode(),1].max
      # Gen 9 Moves
      when 0x506 # Axe Kick
        miniscore = jumpcode(score)
        if @attacker.index != 2 && @mondata.skill>=BESTSKILL
          miniscore*= 0.5 if @battle.FE != :INVERSE && pbPartyHasType?(:GHOST, @opponent.index)
        end
        miniscore *= confucode()
      when 0x507 # Gen 9 Mod - Alluring Voice
        miniscore = confucode() if ((checkAImoves(PBStuff::SETUPMOVE) && !pbAIfaster?()) || @opponent.effects[:Jealousy]) && @move.move == :ALLURINGVOICE
      # Gen 9 Mod - New Gen 9 Moves
      when 0x902 # Burning Bulwark
        miniscore = protecteffectcode()
        if !@opponent.status.nil?
          miniscore *= 0.8
        elsif @opponent.pbCanBurn?(false)
          miniscore *= 1.3
          miniscore *= 1.3 if pbRoughStat(@opponent,PBStats::ATTACK) > pbRoughStat(@opponent, PBStats::SPATK)
          miniscore *= 0.3 if @opponent.ability == :GUTS || @opponent.ability == :FLAREBOOST
        end
      when 0x903 # Chilly Reception
        miniscore = pivotcode()
        miniscore *= hailcode()
      when 0x905 # Doodle
        miniscore = doodlecode()
      when 0x906 # Double Shock
        miniscore = doubleshockcode()
      when 0x907 # Dragon Cheer
        miniscore = dragoncheercode()
      when 0x908 # Electro Shot
        statarray = [0,0,1,0,0,0,0]
        if @attacker.ability == :CONTRARY
          miniscore = selfstatdrop(statarray,score)
        else
          miniscore = selfstatboost(statarray)
        end
        miniscore *= weaselslashcode() unless @battle.pbWeather == :RAINDANCE
      when 0x90A # Fillet Away
        miniscore = selfstatboost([2,0,2,0,2,0,0])
        miniscore *= 0.3 if !@attacker.moves.any?{|moveloop| moveloop!=nil && moveloop.basedamage > 0 && moveloop.pbIsPriorityMoveAI(@attacker)} && !pbAIfaster?()
        miniscore *= 1.2 if @attacker.turncount<1
        miniscore = 1 if (@attacker.hp.to_f)/@attacker.totalhp <= 0.5
      when 0x90B # Flower Trick
        miniscore = nevermisscode(initialscores[scoreindex])
        miniscore *= permacritcode(initialscores[scoreindex])
      when 0x90C # Glaive Rush
        miniscore*= 1.4 if ((pbRoughDamage > @opponent.hp) && pbAIfaster?())    # If we're going to knock out the opponent and are faster, the downside of Glaive Rush isn't a huge deal, since we're comparatively fast, so the next thing sent in likely won't act before us. (Kinda flimsy logic, but it works well enough in practice).
        miniscore*= 1.1 if ((pbRoughDamage > @opponent.hp) && !pbAIfaster?())   # If we're going to knock out the opponent and aren't faster, the downside of Glaive Rush isn't a big deal, but we might have to switch out or get knocked out next turn since we're comparatively slow, so the next thing sent in likely would be able to act before us. (Kinda flimsy logic, but it works well enough in practice).
        miniscore*= 0.9 if (!(pbRoughDamage > @opponent.hp) && !pbAIfaster?())  # if we're not going to knock out the opponent and aren't faster, next turn their move will hurt a lot so we might have to switch or get knocked out.
        miniscore*= 0.7 if (!(pbRoughDamage > @opponent.hp) && pbAIfaster?())   # If we're not going to knock out the opponent and are faster, their move this turn will hurt a lot and we might get knocked out.
      when 0x90E # Hyper Drill / Mighty Cleave
         # They technically don't break also protect for other moves, but
         # just using feintcode is a quick solution which is 99% correct.
        miniscore = feintcode()
      when 0x910 # Last Respects
        miniscore = (1.3 ** @attacker.pbFaintedPokemonCount)
      when 0x911 # Make It Rain
        statarray = [0,0,1,0,0,0,0]
        if @attacker.ability == :CONTRARY
          miniscore = selfstatboost(statarray)
        else
          miniscore = selfstatdrop(statarray,score)
          miniscore *=1.3 if @attacker.ability == :SOULHEART
        end
      when 0x912 # Matcha Gotcha
        miniscore = absorbcode(initialscores[scoreindex])
        miniscore *= burncode()
      when 0x913 # Order Up
        statarray = [0,0,0,0,0,0,0]
        if @attacker.effects[:Commandee] && @attacker.pbPartner.effects[:Commander]
          case @attacker.pbPartner.form
            when 0
              statarray = [1,0,0,0,0,0,0]
            when 1
              statarray = [0,1,0,0,0,0,0]
            when 2
              statarray = [0,0,0,0,1,0,0]
          end
          if @attacker.ability == :CONTRARY
            miniscore = selfstatdrop(statarray,score)
          else
            miniscore = selfstatboost(statarray)
          end
        end
      when 0x914 # Population Bomb
        miniscore = multihitcode() * 1.2 # More extreme scoring
      when 0x916 # Raging Bull
        miniscore = brickbreakcode()
      when 0x917 # Revival Blessing
        miniscore = revivalcode
      when 0x918 # Salt Cure
        miniscore = saltcurecode()
      when 0x919 # Shed Tail
        miniscore = shedtailcode()
      when 0x91A # Silk Trap
        miniscore = protecteffectcode()
      when 0x91C # Spicy Extract
        if @opponent.ability == :CONTRARY
          miniscore = oppstatboost([0, 2, 0, 0, 0], false, true)
          miniscore *= oppstatdrop([2, 0, 0, 0, 0, 0, 0])
        else
          miniscore = oppstatboost([2, 0, 0, 0, 0], false, true)
          miniscore *= oppstatdrop([0, 2, 0, 0, 0, 0, 0])
        end
      when 0x91D # Spin Out
        statarray = [0,0,0,0,2,0,0]
        if @attacker.ability == :CONTRARY
          miniscore = selfstatboost(statarray)
        else
          miniscore = selfstatdrop(statarray,score)
        end
      when 0x91E # Syrup Bomb - Simple ai only considering one turn, mirroring Octolock's implementation.
        miniscore = oppstatdrop([0,0,0,0,1,0,0])
      when 0x91F # Tachyon Cutter
        miniscore = nevermisscode(initialscores[scoreindex])
        miniscore *= multihitcode()
      when 0x921 # Tidy Up
        miniscore = tidyupcode()
        statarray = [1,0,0,0,1,0,0]
        miniscore += selfstatboost(statarray)
      when 0x922 # Triple Dive
        miniscore = multihitcode()
      when 0x923 # Upper Hand
        if (@opponent.ability == :GALEWINGS && (@opponent.hp >= @opponent.totalhp / 2 || @battle.FE == :SKY)) || checkAIpriority()
          miniscore = suckercode()
        else
          miniscore = 0
        end
      # Rejuv Customs
      when 0x200 # Decimation
        miniscore = moldbreakeronalaser()
        miniscore *= petrifycode()
      when 0x201 # Gale Strike
        miniscore = permacritcode(initialscores[scoreindex]) if @attacker.hp<=((@attacker.totalhp)*0.5).floor
      when 0x202 # Fever Pitch
        miniscore = 1.0
        miniscore = 1.5 if @attacker.status == :SLEEP
        if @battle.FE == :VOLCANICTOP
          miniscore*=volcanoeruptioncode()
        end
      when 0x203 # Arenite Wall
        miniscore = screencode()
      #when 0x204 # Matrix shot # handled in damage calc
      when 0x205 # Desert's Mark
        miniscore = opptypechangecode(:GROUND)
        miniscore *= firespincode()
        # addition for the sandstorm chip marker
      #when 0x206 # Probopog # does this *need* AI?? i don't think it does
      when 0x207 # Aquabatics
        statarray = [0,0,1,0,1,0,0]
        statarray = [0,0,2,0,2,0,0] if @mondata.skill >= BESTSKILL && (@battle.FE == :BIGTOP)
        miniscore = selfstatboost(statarray)
      when 0x208 # Hexing Slash
        miniscore = absorbcode(initialscores[scoreindex])
        miniscore *= poisoncode()
      when 0x20A # Quicksilver Spear
        miniscore = oppstatdrop([0,0,0,0,1,0,0])
      when 0x20B #Spectral Scream
        miniscore = selfstatboost([0,2,0,0,0,0,0]) +selfstatboost([0,0,0,2,0,0,0])
        miniscore/=2
      #when 0x20C # Gilded Arrow / Gilded Helix
      when 0x20D # Super Ultra Mega Death Move
        if move.category == :physical
          miniscore = oppstatdrop([0,1,0,0,0,0,0])
        else
          miniscore = oppstatdrop([0,0,0,1,0,0,0])
        end
      #Z-moves
      when 0x800 # Acid Downpour
        miniscore = (burncode() + paracode() + (KAIZOMOD ? frostbitecode() : freezecode()) + poisoncode()) / 4 if @battle.FE == :WASTELAND
      when 0x801 # Bloom Doom
        miniscore = grassyterraincode() unless @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN)
      when 0x802 # Shattered Psyche
        miniscore = confucode() if @battle.FE == :PSYTERRAIN
      when 0x803 # Stoked Sparksurfer
        miniscore = paracode()
        miniscore *= electricterraincode()
      when 0x804 # Extreme Evoboost
        miniscore = selfstatboost([2,2,2,2,2,0,0])
      when 0x805 # Genesis Supernova
        miniscore = psychicterraincode()
      when 0x807 # Splintered Stormshards
        miniscore = getFieldDisruptScore(@attacker,@opponent)
      when 0x808 # Clangorous Soulblaze
        miniscore = selfstatboost([1,1,1,1,1,0,0])
      when 0x809 # Guardian of Alola
        basescore = 0
        if (attacker.species == :TAPUKOKO)
          basescore += paracode()
        elsif (attacker.species == :TAPULELE)
          basescore += healblockcode() + meanlookcode()
        elsif (attacker.species == :TAPUFINI)
          basescore += hazecode() + defogcode()
        elsif (attacker.species == :TAPUBULU)
          basescore += absorbcode(initialscores[scoreindex])
        end
        return basescore
      when 0x80A # Unleashed Power
        miniscore = brickbreakcode()
        miniscore *= feintcode()
      when 0x80B # Blinding Speed
        miniscore = afteryoucode()
      when 0x80C # Elysian Shield
        miniscore = screencode()
        miniscore *= selfstatboost([0,1,0,1,0,0,0])
      when 0x80D # Domain Shift
        #help why is AI using this
      when 0x80E # Chthonic Malady
        miniscore = petrifycode()
        miniscore *= tormentcode()
        miniscore *= oppstatdrop([2,0,2,0,0,0,0])
      # SWu Moves
      when 0x900 # Barbed Web
        if @attacker.pbOpposingSide.effects[:Spikes] < 3 || @attacker.pbOpposingSide.effects[:ToxicSpikes] < 2
          miniscore = hazardcode()
          miniscore *= 0.9 if @attacker.pbOpposingSide.effects[:Spikes] > 0 && @attacker.pbOpposingSide.effects[:ToxicSpikes] > 0
          if @mondata.skill>=BESTSKILL
            miniscore = 0 if @battle.FE == :WATERSURFACE || @battle.FE == :MURKWATERSURFACE # (Murk)Water Surface
            miniscore *= 1.3 if Rejuv && @battle.FE == :ELECTERRAIN
          end
        end
      # Giga Moves
      when 0x1000 # Resonance
        miniscore = screencode()
      when 0x1001 # Snooze
        miniscore = sleepcode()

    end
    miniscore *= recoilcode() if @move.recoil > 0
    miniscore *= cooldownmovecode() if @move.hasFlag?(:cooldown)
    score*=miniscore
    score=score.to_i
    score=0 if score<0
    $ai_log_data[@attacker.index].final_score_moves.push(score)
    return score
  end
######################################################
# Function (code) subfunctions
######################################################
#All functions here return a modifier to the original score, similar to miniscore
  def sleepcode
    moldbroken = moldBreakerCheck(@attacker) # Gen 9 Mod - Proper Mold Braker Check
    moldbroken = myceliumMightCheck(@attacker) if !moldbroken # Gen 9 Mod - Added Mycelium Might
    return @move.basedamage > 0 ? 1 : 0 if !(@opponent.pbCanSleep?(false, false, false, moldbroken) && @opponent.effects[:Yawn]==0) # Gen 9 Mod - Proper Mold Braker Check
    return @move.basedamage > 0 ? 1 : 0 if secondaryEffectNegated?()
    return @move.basedamage > 0 ? 1 : 0 if hydrationCheck(@opponent)
    return @move.basedamage > 0 ? 1 : 0 if @move.move == :DARKVOID && !(attacker.species == :DARKRAI || (attacker.species == :HYPNO && attacker.form == 1))
    miniscore = 1.2
    if @attacker.pbHasMove?(:DREAMEATER) || @attacker.pbHasMove?(:NIGHTMARE) || @attacker.ability == :BADDREAMS
      miniscore *= 1.5
    end
    miniscore*=(1.2*hpGainPerTurn)
    miniscore*=2 if (attacker.species == :HYPNO && attacker.form == 1)
    miniscore*=1.3 if @attacker.moves.any? {|moveloop| moveloop!=nil && (PBStuff::SETUPMOVE).include?(moveloop.move)}
    miniscore*=1.3 if @attacker.pbHasMove?(:LEECHSEED)
    miniscore*=1.3 if @attacker.pbHasMove?(:SUBSTITUTE)
    miniscore*=1.2 if @opponent.hp==@opponent.totalhp
    miniscore*=0.1 if checkAImoves([:SLEEPTALK,:SNORE])
    # Gen 9 Mod - Discourage status moves when current opponent has Good as Gold
    miniscore*=0 if @opponent.ability == :GOODASGOLD && @move.category == :status && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))
    miniscore*=0.1 if @opponent.ability == :NATURALCURE
    miniscore*=0.8 if @opponent.ability == :MARVELSCALE
    miniscore*=0.5 if @opponent.ability == :SYNCHRONIZE && @attacker.pbCanSleep?(false)
    miniscore*=0.4 if @opponent.effects[:Confusion]>0
    miniscore*=0.5 if @opponent.effects[:Attract]>=0
    ministat = statchangecounter(@opponent,1,7)
    miniscore*= 1 + 0.1*ministat if ministat>0
    if @mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL) || @mondata.roles.include?(:CLERIC) || @mondata.roles.include?(:PIVOT)
      miniscore*=1.2
    end
    if @initial_scores.length>0
      miniscore*=1.3 if hasbadmoves(40)
      miniscore*=1.5 if hasbadmoves(20)
    end
    miniscore = pbSereneGraceCheck(miniscore) if @move.basedamage>0
    miniscore = pbReduceWhenKills(miniscore)
    return miniscore
  end

  def poisoncode
    moldbroken = moldBreakerCheck(@attacker) # Gen 9 Mod - Proper Mold Braker Check
    moldbroken = myceliumMightCheck(@attacker) if !moldbroken # Gen 9 Mod - Added Mycelium Might
    return @move.basedamage > 0 ? 1 : 0 if !@opponent.pbCanPoison?(false, false, @move.move==:TOXIC && @attacker.ability==:CORROSION, moldbroken) # Gen 9 Mod - Proper Mold Braker Check
    return @move.basedamage > 0 ? 1 : 0 if hydrationCheck(@opponent)
    return @move.basedamage > 0 ? 1 : 0 if secondaryEffectNegated?()
    miniscore=1.2
    ministat=0
    ministat+=@opponent.stages[PBStats::DEFENSE]
    ministat+=@opponent.stages[PBStats::SPDEF]
    ministat+=@opponent.stages[PBStats::EVASION]
    miniscore*=1+0.05*ministat if ministat>0
    miniscore*=2 if @move.function == 0x06 && checkAIhealing()
    miniscore*=0.3 if @opponent.ability == :NATURALCURE
    miniscore*=0.7 if @opponent.ability == :MARVELSCALE
    # Gen 9 Mod - Discourage status moves when current opponent has Good as Gold
    miniscore*=0 if @opponent.ability == :GOODASGOLD && @move.category == :status && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))
    miniscore*=0.2 if @opponent.ability == :TOXICBOOST || @opponent.ability == :GUTS || @opponent.ability == :QUICKFEET
    miniscore*=0.1 if @opponent.ability == :POISONHEAL || @opponent.crested == :ZANGOOSE || @opponent.ability == :MAGICGUARD || (@opponent.ability == :WONDERGUARD && @battle.FE == :COLOSSEUM)
    miniscore*=0.7 if @opponent.ability == :SHEDSKIN
    miniscore*=1.1 if (@opponent.ability == :STURDY || (@battle.FE == :CHESS && @opponent.pokemon.piece==:PAWN) || (@battle.FE == :COLOSSEUM && @opponent.ability == :STALWART)) && @move.basedamage>0
    miniscore*=0.5 if @opponent.ability == :SYNCHRONIZE && @attacker.status.nil? && !@attacker.hasType?(:POISON) && !@attacker.hasType?(:STEEL)
    miniscore*=0.2 if checkAImoves([:FACADE])
    miniscore*=0.1 if checkAImoves([:REST])
    miniscore*=1.5 if @mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL)
    if @initial_scores.length>0
      miniscore*=1.2 if hasbadmoves(30)
    end
    if @attacker.pbHasMove?(:VENOSHOCK) || @attacker.pbHasMove?(:VENOMDRENCH) || @attacker.ability == :MERCILESS || @attacker.crested == :ARIADOS
      miniscore*=1.6
    end
    miniscore*=0.4 if @opponent.effects[:Yawn]>0
    miniscore = pbSereneGraceCheck(miniscore) if @move.basedamage>0
    miniscore = pbReduceWhenKills(miniscore)
    return miniscore
  end

  def paracode
    moldbroken = moldBreakerCheck(@attacker) # Gen 9 Mod - Proper Mold Braker Check
    moldbroken = myceliumMightCheck(@attacker) if !moldbroken # Gen 9 Mod - Added Mycelium Might
    return @move.basedamage > 0 ? 1 : 0 if !@opponent.pbCanParalyze?(false, moldbroken) # Gen 9 Mod - Proper Mold Braker Check
    return @move.basedamage > 0 ? 1 : 0 if hydrationCheck(@opponent)
    return @move.basedamage > 0 ? 1 : 0 if secondaryEffectNegated?()
    return @move.basedamage > 0 ? 1 : 0 if @move.move==:THUNDERWAVE && @move.pbTypeModifier(@move.pbType(@attacker),@attacker,@opponent)==0
    miniscore=1.0
    miniscore*=1.1 if @attacker.moves.any? {|moveloop| moveloop!=nil && (PBStuff::SETUPMOVE).include?(moveloop.move)}
    miniscore*=1.2 if @opponent.hp==@opponent.totalhp
    ministat= @opponent.stages[PBStats::ATTACK] + @opponent.stages[PBStats::SPATK] + @opponent.stages[PBStats::SPEED]
    miniscore*=1+0.05*ministat if ministat>0
    miniscore*=0.3 if @opponent.ability == :NATURALCURE
    miniscore*=0.5 if @opponent.ability == :MARVELSCALE
    # Gen 9 Mod - Discourage status moves when current opponent has Good as Gold
    miniscore*=0 if @opponent.ability == :GOODASGOLD && @move.category == :status && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))
    miniscore*=0.2 if @opponent.ability == :GUTS || @opponent.ability == :QUICKFEET
    miniscore*=0.7 if @opponent.ability == :SHEDSKIN
    miniscore*=0.5 if @opponent.ability == :SYNCHRONIZE && @attacker.pbCanParalyze?(false)
    miniscore*=1.2 if @mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL) || @mondata.roles.include?(:PIVOT)
    miniscore*=1.3 if @mondata.roles.include?(:TANK)
    if !pbAIfaster?() && (pbRoughStat(@opponent,PBStats::SPEED)/2.0)<@attacker.pbSpeed && @battle.trickroom==0
      miniscore*=1.2
    elsif pbAIfaster?() && (pbRoughStat(@opponent,PBStats::SPEED)/2.0)<@attacker.pbSpeed && @battle.trickroom>1
      miniscore*=0.7
    end
    if pbRoughStat(@opponent,PBStats::SPATK)>pbRoughStat(@opponent,PBStats::ATTACK)
      miniscore*=1.1
    end
    miniscore*=1.1 if @mondata.partyroles.any? {|roles| roles.include?(:SWEEPER)}
    miniscore*=1.1 if @opponent.effects[:Confusion]>0
    miniscore*=1.1 if @opponent.effects[:Attract]>=0
    miniscore*=0.4 if @opponent.effects[:Yawn]>0
    miniscore = pbSereneGraceCheck(miniscore) if @move.basedamage>0
    miniscore = pbReduceWhenKills(miniscore)
    if !pbAIfaster?() && (pbRoughStat(@opponent,PBStats::SPEED)/2.0)<@attacker.pbSpeed && @battle.trickroom==0
      if hasbadmoves(40)
        # Gen 9 Mod - Added Covert Cloak
        miniscore+=25 if @move.effect == 100 && !@opponent.item == :COVERTCLOAK # help nuzzle
      end
    end
    return miniscore
  end

  def burncode
    moldbroken = moldBreakerCheck(@attacker) # Gen 9 Mod - Proper Mold Braker Check
    moldbroken = myceliumMightCheck(@attacker) if !moldbroken # Gen 9 Mod - Added Mycelium Might
    return @move.basedamage > 0 ? 1 : 0 if !@opponent.pbCanBurn?(false, false, moldbroken) # Gen 9 Mod - Proper Mold Braker Check
    return @move.basedamage > 0 ? 1 : 0 if hydrationCheck(@opponent)
    return @move.basedamage > 0 ? 1 : 0 if secondaryEffectNegated?()
    miniscore=1.2
    ministat=0
    ministat+=@opponent.stages[PBStats::ATTACK]
    ministat+=@opponent.stages[PBStats::SPATK]
    ministat+=@opponent.stages[PBStats::SPEED]
    miniscore*=1+0.05*ministat if ministat>0
    miniscore*=0.3 if @opponent.ability == :NATURALCURE
    miniscore*=0.7 if @opponent.ability == :MARVELSCALE
    # Gen 9 Mod - Discourage status moves when current opponent has Good as Gold
    miniscore*=0 if @opponent.ability == :GOODASGOLD && @move.category == :status && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))
    miniscore*=0.1 if @opponent.ability == :GUTS || @opponent.ability == :FLAREBOOST
    miniscore*=0.7 if @opponent.ability == :SHEDSKIN
    miniscore*=0.5 if @opponent.ability == :SYNCHRONIZE && @attacker.pbCanBurn?(false)
    miniscore*=0.5 if @opponent.ability == :MAGICGUARD || (@opponent.ability == :WONDERGUARD && @battle.FE == :COLOSSEUM)
    miniscore*=0.3 if @opponent.ability == :QUICKFEET
    miniscore*=1.1 if (@opponent.ability == :STURDY || (@battle.FE == :CHESS && @opponent.pokemon.piece==:PAWN) || (@battle.FE == :COLOSSEUM && @opponent.ability == :STALWART)) && @move.basedamage>0
    miniscore*=0.1 if checkAImoves([:REST])
    miniscore*=0.3 if checkAImoves([:FACADE])
    if pbRoughStat(@opponent,PBStats::ATTACK)>pbRoughStat(@opponent,PBStats::SPATK)
      miniscore*=1.4
    end
    miniscore*=0.4 if @opponent.effects[:Yawn]>0
    miniscore = pbSereneGraceCheck(miniscore) if @move.basedamage>0
    miniscore = pbReduceWhenKills(miniscore)
    return miniscore
  end

  def freezecode
    moldbroken = moldBreakerCheck(@attacker) # Gen 9 Mod - Proper Mold Braker Check
    moldbroken = myceliumMightCheck(@attacker) if !moldbroken # Gen 9 Mod - Added Mycelium Might
    return @move.basedamage > 0 ? 1 : 0 if !@opponent.pbCanFreeze?(false, moldbroken) # Gen 9 Mod - Proper Mold Braker Check
    return @move.basedamage > 0 ? 1 : 0 if hydrationCheck(@opponent)
    return @move.basedamage > 0 ? 1 : 0 if secondaryEffectNegated?()
    miniscore=1.2
    miniscore*=0 if checkAImoves(PBStuff::UNFREEZEMOVE)
    miniscore*=1.2 if @attacker.moves.any? {|moveloop| moveloop!=nil && (PBStuff::SETUPMOVE).include?(moveloop.move)}
    miniscore*=1.2 if checkAIhealing()
    ministat = statchangecounter(@opponent,1,7)
    miniscore*=1+0.05*ministat if ministat>0
    miniscore*=0.3 if @opponent.ability == :NATURALCURE
    miniscore*=0.8 if @opponent.ability == :MARVELSCALE
    # Gen 9 Mod - Discourage status moves when current opponent has Good as Gold
    miniscore*=0 if @opponent.ability == :GOODASGOLD && @move.category == :status && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))
    miniscore*=0.5 if @opponent.ability == :SYNCHRONIZE && @attacker.pbCanFreeze?(false)
    miniscore = pbSereneGraceCheck(miniscore) if @move.basedamage>0
    miniscore = pbReduceWhenKills(miniscore)
    return miniscore
  end

  def frostbitecode
    moldbroken = moldBreakerCheck(@attacker) # Gen 9 Mod - Proper Mold Braker Check
    moldbroken = myceliumMightCheck(@attacker) if !moldbroken # Gen 9 Mod - Added Mycelium Might
    return @move.basedamage > 0 ? 1 : 0 if !@opponent.pbCanFreeze?(false, moldbroken) # Gen 9 Mod - Proper Mold Breaker Check
    return @move.basedamage > 0 ? 1 : 0 if hydrationCheck(@opponent)
    return @move.basedamage > 0 ? 1 : 0 if secondaryEffectNegated?()
    miniscore=1.2
    ministat=0
    ministat+=@opponent.stages[PBStats::ATTACK]
    ministat+=@opponent.stages[PBStats::SPATK]
    ministat+=@opponent.stages[PBStats::SPEED]
    miniscore*=1+0.05*ministat if ministat>0
    miniscore*=0.3 if @opponent.ability == :NATURALCURE
    miniscore*=0.7 if @opponent.ability == :MARVELSCALE
    # Gen 9 Mod - Discourage status moves when current opponent has Good as Gold
    miniscore*=0 if @opponent.ability == :GOODASGOLD && @move.category == :status && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))
    miniscore*=0.2 if @opponent.ability == :GUTS
    miniscore*=0.7 if @opponent.ability == :SHEDSKIN
    miniscore*=0.5 if @opponent.ability == :SYNCHRONIZE && @attacker.pbCanFreeze?(false)
    miniscore*=0.5 if @opponent.ability == :MAGICGUARD || (@opponent.ability == :WONDERGUARD && @battle.FE == :COLOSSEUM)
    miniscore*=0.3 if @opponent.ability == :QUICKFEET
    miniscore*=1.1 if (@opponent.ability == :STURDY || (@battle.FE == :CHESS && @opponent.pokemon.piece==:PAWN) || (@battle.FE == :COLOSSEUM && @opponent.ability == :STALWART)) && @move.basedamage>0
    miniscore*=0.1 if checkAImoves([:REST])
    miniscore*=0.2 if checkAImoves([:FACADE])
    if pbRoughStat(@opponent,PBStats::SPATK)>pbRoughStat(@opponent,PBStats::ATTACK)
      miniscore*=1.4
    end
    miniscore*=0.4 if @opponent.effects[:Yawn]>0
    miniscore = pbSereneGraceCheck(miniscore) if @move.basedamage>0
    miniscore = pbReduceWhenKills(miniscore)
    return miniscore
  end

  def petrifycode
    return @move.basedamage > 0 ? 1 : 0 if !@opponent.pbCanPetrify?(false)
    return @move.basedamage > 0 ? 1 : 0 if hydrationCheck(@opponent)
    return @move.basedamage > 0 ? 1 : 0 if secondaryEffectNegated?()
    return @move.basedamage > 0 ? 1 : 0 if @opponent.ability == :LIQUIDOOZE
    miniscore=1.2
    miniscore*=1.2 if (@mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL) || @mondata.roles.include?(:TANK))
    miniscore*=1.3 if @attacker.effects[:Substitute]>0
    miniscore*=1.2 if hpGainPerTurn(@opponent)>1 || (@mondata.attitemworks && @attacker.item == :BIGROOT) || @attacker.crested == :SHIINOTIC
    miniscore*=0 if @opponent.ability == :LIQUIDOOZE
    miniscore*=0.3 if @opponent.ability == :NATURALCURE
    miniscore*=0.7 if @opponent.ability == :MARVELSCALE
    miniscore*=0.1 if @opponent.ability == :GUTS
    miniscore*=0.7 if @opponent.ability == :SHEDSKIN
    miniscore*=0.5 if @opponent.ability == :SYNCHRONIZE && @attacker.pbCanPetrify?(false)
    miniscore*=0.5 if @opponent.ability == :MAGICGUARD || (@opponent.ability == :WONDERGUARD && @battle.FE == :COLOSSEUM)
    miniscore*=0.3 if @opponent.ability == :QUICKFEET
    miniscore*=1.1 if (@opponent.ability == :STURDY || (@battle.FE == :CHESS && @opponent.pokemon.piece==:PAWN) || (@battle.FE == :COLOSSEUM && @opponent.ability == :STALWART)) && @move.basedamage>0
    miniscore*=0.1 if checkAImoves([:REST])
    miniscore*=0.3 if checkAImoves([:FACADE])
    return miniscore
  end

  def flinchcode
    return @move.basedamage > 0 ? 1 : 0 if @opponent.effects[:Substitute] > 0 || @opponent.ability == :INNERFOCUS || secondaryEffectNegated?()
    return @move.basedamage > 0 ? 1 : 0 if !pbAIfaster?(@move)

    miniscore = 1.0
    miniscore *= 1.3 if !hasgreatmoves()
    miniscore *= 1.3 if @battle.trickroom > 0 && @attacker.pbSpeed > pbRoughStat(@opponent, PBStats::SPEED)
    miniscore *= 1.3 if @battle.field.duration > 0 && getFieldDisruptScore(@attacker, @opponent) > 1.0
    miniscore *= 1.3 if @attacker.pbOpposingSide.screenActive?
    miniscore *= 1.2 if @attacker.pbOpposingSide.effects[:Tailwind] > 0
    # Gen 9 Mod - Hail/Snow/Both consider HAIL only when it is damaging
    if @opponent.status== :POISON || @opponent.status== :BURN || (@battle.pbWeather == :HAIL && !@opponent.hasType?(:ICE) && (HAILSNOWMOD != "Snow") || KAIZOMOD) || (@battle.pbWeather == :SANDSTORM && !@opponent.hasType?(:ROCK) && !@opponent.hasType?(:GROUND) && !@opponent.hasType?(:STEEL)) || (@battle.pbWeather == :SHADOWSKY && !@opponent.hasType?(:SHADOW)) || @opponent.effects[:LeechSeed]>-1 || @opponent.effects[:Curse] || @opponent.effects[:SaltCure]
      miniscore *= 1.1
      miniscore *= 1.2 if @opponent.effects[:Toxic]>0 && (@opponent.ability != :POISONHEAL || @opponent.ability != :MAGICGUARD || @opponent.crested != :ZANGOOSE) # Gen 9 Mod - Checks for abilities, Crest
      # Gen 9 Mod - Additions for Salt Cure since it does even more damage than burn/weather.
      miniscore *= 1.1 if @opponent.effects[:SaltCure] && @opponent.ability != :MAGICGUARD
      miniscore *= 1.2 if @opponent.effects[:SaltCure] && @opponent.ability != :MAGICGUARD && (@opponent.hasType?(:WATER) || @opponent.hasType?(:STEEL))
    end
    miniscore *= 0.3 if @opponent.ability == :STEADFAST
    if @mondata.skill >= BESTSKILL
      miniscore *= 1.1 if @battle.FE == :ROCKY # Rocky
    end
    miniscore = pbSereneGraceCheck(miniscore) if @move.basedamage > 0
    miniscore = pbReduceWhenKills(miniscore)
    return miniscore
  end

  def thunderboostcode
    miniscore = 1.0
    invulmove=$cache.moves[@opponent.effects[:TwoTurnAttack]].function rescue nil
    if invulmove==0xC9 || invulmove==0xCC || invulmove==0xCE
      miniscore*=2 if pbAIfaster?()
    end
    if !pbAIfaster?()
      miniscore*=1.2 if checkAImoves(PBStuff::TWOTURNAIRMOVE)
    end
    return miniscore
  end

  def confucode
    return @move.basedamage > 0 ? 1 : 0 if !@opponent.pbCanConfuse?(false, inflictor: @attacker)
    return @move.basedamage > 0 ? 1 : 0 if secondaryEffectNegated?()

    miniscore = 1.0
    miniscore *= 1.2 if !hasgreatmoves()
    miniscore *= 1 + 0.1 * @opponent.stages[PBStats::ATTACK] if @opponent.stages[PBStats::ATTACK] > 0
    if pbRoughStat(@opponent, PBStats::ATTACK) > pbRoughStat(@opponent, PBStats::SPATK)
      miniscore *= 1.2
    end
    miniscore *= 1.3 if @mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL)
    miniscore *= 1.1 if @opponent.effects[:Attract] >= 0
    miniscore *= 1.1 if @opponent.status == :PARALYSIS
    # Gen 9 Mod - Discourage status moves when current opponent has Good as Gold
    miniscore *= 0 if @opponent.ability == :GOODASGOLD && @move.category == :status && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))
    miniscore *= 0.7 if @opponent.ability == :TANGLEDFEET
    if @attacker.pbHasMove?(:SUBSTITUTE)
      miniscore *= 1.2
      miniscore *= 1.3 if @attacker.effects[:Substitute] > 0
    end
    if @initial_scores.length > 0
      miniscore *= 1.4 if hasbadmoves(40)
    end
    miniscore = pbSereneGraceCheck(miniscore) if @move.basedamage > 0
    miniscore = pbReduceWhenKills(miniscore)
    return miniscore
  end

  def attractcode # Gen 9 Mod - Added myceliumMightCheck
    agender=@attacker.gender
    ogender=@opponent.gender
    return 0 if (((agender==2 || ogender==2 || agender==ogender) && !KAIZOMOD) || @opponent.effects[:Attract]>=0 || ((@opponent.ability == :OBLIVIOUS || @opponent.ability == :AROMAVEIL || @opponent.pbPartner.ability == :AROMAVEIL) && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))))
    miniscore=1.2
    miniscore*=0.7 if @attacker.ability == :CUTECHARM
    miniscore*=1.3 if @mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL)
    miniscore*=1.1 if @opponent.effects[:Confusion]>0
    miniscore*=1.1 if @opponent.status== :PARALYSIS
    miniscore*=0.5 if @opponent.effects[:Yawn]>0 || @opponent.status== :SLEEP
    miniscore*=0.1 if (@mondata.oppitemworks && @opponent.item == :DESTINYKNOT)
    if @attacker.pbHasMove?(:SUBSTITUTE)
      miniscore*=1.2
      miniscore*=1.3 if @attacker.effects[:Substitute]>0
    end
    return miniscore
  end

  def refreshcode
    miniscore = 1.0
    if @attacker.status== :BURN || @attacker.status== :POISON || @attacker.status== :PARALYSIS
      miniscore*=3
    else
      return 0
    end
    miniscore*=((@attacker.hp.to_f)/@attacker.totalhp > 0.5) ? 1.5 : 0.3
    miniscore*=0.1 if @opponent.effects[:Yawn] > 0
    miniscore*=0.1 if checkAIdamage() > @attacker.hp
    miniscore*=1.3 if @opponent.effects[:Toxic] > 2
    miniscore*=1.3 if checkAImoves([:HEX])
    return miniscore
  end

  def partyrefreshcode
    return 0 if !@battle.pbPartySingleOwner(@attacker.index).any? {|mon| mon && !mon.status.nil?}
    miniscore=1.2
    for mon in @battle.pbPartySingleOwner(@attacker.index)
      next if mon.nil? || mon.hp <= 0 || mon.isEgg? || mon.status.nil?
      miniscore*=0.5 if mon.status== :POISON && mon.ability == :POISONHEAL
      miniscore*=0.8 if mon.ability == :GUTS || mon.ability == :QUICKFEET || mon.knowsMove?(:FACADE)
      miniscore*=1.1 if mon.status== :SLEEP || (mon.status== :FROZEN && !KAIZOMOD)
      monroles=pbGetMonRoles(mon)
      miniscore*=1.2 if (monroles.include?(:PHYSICALWALL) || monroles.include?(:SPECIALWALL)) && mon.status== :POISON
      miniscore*=1.2 if monroles.include?(:SWEEPER) && mon.status== :PARALYSIS
      miniscore*=1.2 if mon.attack>mon.spatk && mon.status== :BURN
    end
    miniscore*=1.3 if !@attacker.status.nil?
    miniscore*=1.3 if @attacker.effects[:Toxic]>2
    miniscore*=1.1 if checkAIhealing()
    return miniscore
  end

  def psychocode
    return 0 if @attacker.status.nil? || !@opponent.status.nil? || @opponent.effects[:Substitute]>0 || @opponent.effects[:Yawn]!=0
    return 0 if @attacker.status== :BURN && !@opponent.pbCanBurn?(false) || @attacker.status== :PARALYSIS && !@opponent.pbCanParalyze?(false) || @attacker.status== :POISON && !@opponent.pbCanPoison?(false)
    miniscore=1.3*1.3
    if @attacker.status== :BURN && @opponent.pbCanBurn?(false)
      miniscore*=1.2 if pbRoughStat(@opponent,PBStats::ATTACK)>pbRoughStat(@opponent,PBStats::SPATK)
      miniscore*=0.7 if @opponent.ability == :FLAREBOOST
    end
    if @attacker.status== :PARALYSIS && @opponent.pbCanParalyze?(false)
      miniscore*=1.1 if pbRoughStat(@opponent,PBStats::ATTACK)<pbRoughStat(@opponent,PBStats::SPATK)
      miniscore*=1.2 if pbAIfaster?(@move)
    end
    if @attacker.status== :POISON && @opponent.pbCanPoison?(false)
      miniscore*=1.1 if checkAIhealing()
      miniscore*=1.4 if @attacker.effects[:Toxic]>0
      miniscore*=0.3 if @opponent.ability == :POISONHEAL
      miniscore*=0.7 if @opponent.ability == :TOXICBOOST
    end
    miniscore*=0.7 if @opponent.ability == :SHEDSKIN || @opponent.ability == :NATURALCURE || @opponent.ability == :GUTS || @opponent.ability == :QUICKFEET || @opponent.ability == :MARVELSCALE
    miniscore*=0.7 if checkAImoves([:FACADE])
    miniscore*=1.3 if checkAImoves([:HEX])
    miniscore*=1.3 if @attacker.pbHasMove?(:HEX)
    return miniscore
  end

  def selfstatboost(stats)
    #stats should be an array of the stat boosts like so: [ATK,DEF,SPE,SPA,SPD,ACC,EVA] with nils in unaffected stats
    #coil, for example, would be [1,1,0,0,0,1,0]
    stats.unshift(0) #this is required to make the next line work correctly
    for i in 1...stats.length
      next if stats[i] == 0
      stats[i]*= 2 if @attacker.ability == :SIMPLE
      #cap boost to the max it can be inscreased
      stats[i] = [6-@attacker.stages[i], stats[i]].min
    end
    if stats[PBStats::ATTACK] != 0 || stats[PBStats::SPATK] != 0
      for j in @attacker.moves
        next if j.nil?
        specmove=true if j.pbIsSpecial?()
        physmove=true if j.pbIsPhysical?()
      end
      stats[PBStats::ATTACK] = 0 if !physmove && @battle.FE != :PSYTERRAIN
      stats[PBStats::SPATK] = 0 if !specmove
    end
    if stats.all? {|a| a.nil? || a==0 } && move.function != 0x37
      return @move.basedamage > 0 ? 1 : 0
    end
    #Function is split into 3 sections- individual stat sections, group stat sections, and collective stat sections.
    #Individual is self explanatory; group stats splits stats into offensive/defensive (sweep/tank) and processese separately
    #Collective checks run on all of the stats.
    miniscore=1.0
    if @move.basedamage == 0
      statsboosted = 0
      for i in 1...stats.length
        statsboosted += stats[i] if stats[i] != nil
      end
      miniscore = statsboosted
      # weight categories based on combinations of boosted stats
      if (stats[PBStats::ATTACK] > 0 || stats[PBStats::SPATK] > 0) && (stats[PBStats::SPEED] > 0) # Speed and offense i.e dragon dance
        miniscore *= 1.8
      elsif (stats[PBStats::ATTACK] > 1 || stats[PBStats::SPATK] > 1) # Double offense i.e swords dance, nasty plot
        miniscore *= 1.5
      elsif (stats[PBStats::ATTACK] > 0 || stats[PBStats::SPATK] > 0) && (stats[PBStats::DEFENSE] > 0 || stats[PBStats::SPDEF] > 0) # Defense and offense i.e bulk up
        miniscore *= 1.5
      elsif (stats[PBStats::DEFENSE] > 0 && stats[PBStats::SPDEF] > 0) # Both defenses i.e cosmic power
        miniscore *= 1.5
      end
    end
    for i in 1...stats.length
      next if stats[i].nil? || stats[i]==0
      case i
        when PBStats::ATTACK
          next if !physmove
          sweep = true
          miniscore*=1.3 if checkAIhealing()
          miniscore*=1.5 if pbAIfaster?() || @attacker.moves.any? {|moveloop| moveloop.priority > 0 && moveloop.pbIsPhysical?(moveloop.pbType(@attacker))}
          miniscore*=0.5 if @attacker.status== :BURN && @attacker.ability != :GUTS
          miniscore*=0.3 if checkAImoves([:FOULPLAY])
          miniscore*=1.4 if notOHKO?(@attacker,@opponent)
          miniscore*=0.6 if checkAIpriority()
          miniscore*=0.6 if (@opponent.ability == :SPEEDBOOST || (@opponent.ability == :MOTORDRIVE && @battle.FE == :ELECTERRAIN) || (@opponent.ability == :STEAMENGINE && [:UNDERWATER,:WATERSURFACE,:VOLCANIC,:VOLCANICTOP,:INFERNAL].include?(@battle.FE)))
        when PBStats::DEFENSE
          tank = true
          if pbRoughStat(@opponent,PBStats::SPATK)<pbRoughStat(@opponent,PBStats::ATTACK)
            if !(@mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL))
              if pbAIfaster?(@move) && (@attacker.hp.to_f)/@attacker.totalhp>0.75
                miniscore*=1.3
              elsif !pbAIfaster?(@move)
                miniscore*=0.7
              end
            end
            miniscore*=1.3
          end
        when PBStats::SPATK
          sweep = true
          miniscore*=1.3 if checkAIhealing()
          miniscore*=1.5 if pbAIfaster?() || @attacker.moves.any? {|moveloop| moveloop.priority > 0 && moveloop.pbIsSpecial?(moveloop.pbType(@attacker))}
          miniscore*=0.5 if @attacker.status== :PARALYSIS
          if notOHKO?(@attacker,@opponent)
            miniscore*=1.4
          end
          miniscore*=0.6 if checkAIpriority()
        when PBStats::SPDEF
          tank = true
          miniscore*=1.1 if @opponent.status== :BURN
          if pbRoughStat(@opponent,PBStats::SPATK)>pbRoughStat(@opponent,PBStats::ATTACK)
            if !(@mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL))
              if pbAIfaster?(@move) && (@attacker.hp.to_f)/@attacker.totalhp>0.75
                miniscore*=1.3
              elsif !pbAIfaster?(@move)
                miniscore*=0.7
              end
            end
            miniscore*=1.3
          end
        when PBStats::SPEED
          sweep = true
          if pbAIfaster?()
            miniscore*=0.8
            miniscore*=0.2 if statsboosted == stats[PBStats::SPEED]
          end
          #Additional check if you're the last mon alive?
          miniscore*=0.2 if @battle.trickroom > 1 || checkAImoves([:TRICKROOM])
          # Skip speed checks if we only have priority damaging moves anyway
          if @attacker.moves.any? { |moveloop|
               moveloop != nil && moveloop.basedamage > 0 && moveloop.priority < 1 && @mondata.roughdamagearray.transpose[@attacker.moves.find_index(moveloop)].max > 10
             } # thank u perry 4 saving me
            # Moxie/Soul Heart
            miniscore *= 1.5 if (physmove && [:MOXIE, :CHILLINGNEIGH, :ASONECHILLING].include?(@attacker.ability)) || (specmove && [:SOULHEART, :GRIMNEIGH, :ASONEGRIM].include?(@attacker.ability))
            if @attacker.attack < @attacker.spatk
              miniscore *= (1 + 0.05 * @attacker.stages[PBStats::SPATK]) if @attacker.stages[PBStats::SPATK] < 0
            else
              miniscore *= (1 + 0.05 * @attacker.stages[PBStats::SPATK]) if @attacker.stages[PBStats::ATTACK] < 0
            end
            ministat = 0
            ministat += @opponent.stages[PBStats::DEFENSE]
            ministat += @opponent.stages[PBStats::SPDEF]
            miniscore *= 1 - 0.05 * ministat if ministat > 0
          end
        when PBStats::ACCURACY
          for j in @attacker.moves
            next if j.nil?
            miniscore*=1.1 if j.basedamage<95
          end
          miniscore*=(1+0.05*@opponent.stages[PBStats::EVASION]) if @opponent.stages[PBStats::EVASION]>0
          if (@mondata.oppitemworks && @opponent.item == :BRIGHTPOWDER) || (@mondata.oppitemworks && @opponent.item == :LAXINCENSE) || accuracyWeatherAbilityActive?(@opponent)
            miniscore*=1.1
          end
        when PBStats::EVASION
          tank = true
          miniscore*=0.2 if @opponent.ability == :NOGUARD || @attacker.ability == :NOGUARD || checkAIaccuracy() || (opponent.ability==:FAIRYAURA && @battle.FE == :FAIRYTALE)
          if (@mondata.attitemworks && @attacker.item == :BRIGHTPOWDER) || (@mondata.attitemworks && @attacker.item == :LAXINCENSE) || accuracyWeatherAbilityActive?(@attacker)
            miniscore*=1.3
          end
      end
    end
    if seedProtection?(@attacker) || (@attacker.effects[:Substitute]>0 || ((@attacker.effects[:Disguise] || (@attacker.effects[:IceFace] && (@opponent.attack > @opponent.spatk || @battle.FE == :FROZENDIMENSION))) && !moldBreakerCheck(@opponent)) && !@battle.doublebattle)
      miniscore*=1.3
    end
    miniscore*=0.5 if (@opponent.effects[:Substitute]>0 || ((@opponent.effects[:Disguise] || (@opponent.effects[:IceFace] && (@attacker.attack > @attacker.spatk || @battle.FE == :FROZENDIMENSION))) && !moldBreakerCheck(@attacker)))
    miniscore*=1.3 if @opponent.status== :SLEEP || (@opponent.status== :FROZEN && !KAIZOMOD)
    miniscore*=1.3 if hasbadmoves(20)
    # Gen 9 Mod - Opportunist
    miniscore*=0.5 if @opponent.ability == :OPPORTUNIST || @opponent.pbPartner.ability == :OPPORTUNIST || @opponent.item == :MIRRORHERB || @opponent.pbPartner.item == :MIRRORHERB
    attackerHPpercent = (@attacker.hp.to_f)/@attacker.totalhp
    if attackerHPpercent > 0.5 && attackerHPpercent < 0.75 && (@attacker.ability == :EMERGENCYEXIT || @attacker.ability == :WIMPOUT || (@attacker.itemWorks? && @attacker.item == :EJECTBUTTON))
      miniscore*=0.3
    elsif attackerHPpercent < 0.33 && move.basedamage==0
      miniscore*=0.3
    end
    if @mondata.skill>=MEDIUMSKILL
      bestmove, maxdam = checkAIMovePlusDamage()
      if maxdam < (@attacker.hp/4.0) && sweep
        miniscore*=1.2
      elsif maxdam < (@attacker.hp/3.0) && tank
        miniscore*=1.1
      elsif maxdam < (@attacker.hp/4.0) && (stats[PBStats::DEFENSE] != 0 && stats[PBStats::SPDEF] != 0) #cosmic power
        miniscore*=1.5
      elsif maxdam < (@attacker.hp/2.0)
        miniscore*=1.1
      elsif move.basedamage == 0
        miniscore*=0.8
        miniscore*=0.3 if !@attacker.moves.any? { |moveloop| moveloop.basedamage > 0 && pbAIfaster?(moveloop,bestmove) }
        #Don't set up if you're gonna die this turn for sure
        miniscore*=0.1 if maxdam > @attacker.hp && !(@attacker.effects[:Substitute]>0 || ((@attacker.effects[:Disguise] || (@attacker.effects[:IceFace] && (@opponent.attack > @opponent.spatk || @battle.FE == :FROZENDIMENSION))) && !moldBreakerCheck(@opponent)) || seedProtection?(@attacker))
      end

      if maxdam * 2 > @attacker.hp + (hpGainPerTurn(@attacker)-1)*@attacker.totalhp && (stats[PBStats::ATTACK]==1 || stats[PBStats::SPATK]==1) &&
        ((bestmove.pbIsPhysical?(bestmove.type) && stats[PBStats::DEFENSE] == 0) || (bestmove.pbIsSpecial?(bestmove.type) && stats[PBStats::SPDEF] == 0)) && move.basedamage == 0
        miniscore*=0.4
      end
    end
    #Don't set up if you're just going to get run over
    if (@opponent.level-10)>@attacker.level
      miniscore*=0.6
      if (@opponent.level-15)>@attacker.level
        miniscore*=0.2
      end
    end
    # Some stats run similar checks
    miniscore *= 0.3 if checkAImovesAllOpponents([:SNATCH])
    if sweep
      ministat = @opponent.stages[PBStats::ATTACK] + @opponent.stages[PBStats::SPATK] + @opponent.stages[PBStats::SPEED]
      miniscore *= (1 + 0.05 * ministat)
      if @attacker.stages[PBStats::SPEED] < 0 && stats[PBStats::SPEED] == 0
        miniscore *= (1 + 0.05 * @attacker.stages[PBStats::SPEED])
      end
      miniscore *= 1.2 if attackerHPpercent > 0.75
      miniscore *= 1.2 if @attacker.turncount < 2
      miniscore *= 1.2 if !@opponent.status.nil?
      if @opponent.effects[:Encore] > 0
        miniscore *= 1.5 if @opponent.moves[(@opponent.effects[:EncoreIndex])].basedamage == 0
      end
      miniscore *= 0.6 if @attacker.effects[:LeechSeed] >= 0 || @attacker.effects[:Attract] >= 0
      miniscore *= 0.5 if checkAImoves(PBStuff::PHASEMOVE)
      miniscore *= 1.3 if @mondata.roles.include?(:SWEEPER)
      if @attacker.status == :PARALYSIS
        miniscore *= 0.5
        miniscore *= 0.5 if stats[PBStats::SPEED] != 0 # stacks
      end
      miniscore *= 0.5 if @attacker.pbCanParalyze?(false) && checkAImoves(PBStuff::PARAMOVE) && @move.basedamage == 0
      miniscore *= 0.7 if @attacker.status == :POISON && @attacker.ability != :POISONHEAL && @attacker.crested != :ZANGOOSE
      miniscore *= 0.6 if @attacker.effects[:Toxic] > 0 && @attacker.ability != :POISONHEAL && @attacker.crested != :ZANGOOSE
      # Gen 9 Mod - Additional Checks for Salt Cure
      miniscore *= 0.6 if @attacker.effects[:SaltCure] && @attacker.ability != :MAGICGUARD
      miniscore *= 0.6 if @attacker.effects[:SaltCure] && @attacker.ability != :MAGICGUARD && (@attacker.hasType?(:WATER) || @attacker.hasType?(:STEEL))
      miniscore *= 0.6 if checkAIpriority()
      miniscore *= 0.6 if (
        @opponent.ability == :SPEEDBOOST ||
        (((@opponent.ability == :MOTORDRIVE && @battle.FE == :ELECTERRAIN) || (@opponent.ability == :STEAMENGINE && [:UNDERWATER, :WATERSURFACE, :VOLCANIC, :VOLCANICTOP, :INFERNAL].include?(@battle.FE))) && (stats[PBStats::SPEED] < 2))
      )
      miniscore *= 1.4 if notOHKO?(@attacker, @opponent)
    else
      miniscore *= 1.1 if attackerHPpercent > 0.75
      miniscore *= 1.1 if @attacker.turncount < 2
      miniscore *= 1.1 if !@opponent.status.nil?
      if @opponent.effects[:Encore] > 0
        if @opponent.moves[(@opponent.effects[:EncoreIndex])].basedamage == 0
          miniscore *= 1.3
          miniscore *= 1.2 if (stats[PBStats::DEFENSE] != 0 && stats[PBStats::SPDEF] != 0)
        end
      end
      miniscore *= 0.2 if checkAImoves(PBStuff::PHASEMOVE)
      miniscore *= 0.7 if @attacker.status == :POISON && @attacker.ability != :POISONHEAL && @attacker.crested != :ZANGOOSE
      miniscore *= 0.2 if @attacker.effects[:Toxic] > 0 && @attacker.ability != :POISONHEAL && @attacker.crested != :ZANGOOSE
      miniscore *= 0.3 if @attacker.effects[:LeechSeed] >= 0 || @attacker.effects[:Attract] >= 0
    end
    if tank
      if @attacker.stages[PBStats::SPDEF] > 0 || @attacker.stages[PBStats::DEFENSE] > 0
        ministat = 0
        ministat += @attacker.stages[PBStats::SPDEF] if stats[PBStats::SPDEF] != 0
        ministat += @attacker.stages[PBStats::DEFENSE] if stats[PBStats::DEFENSE] != 0
        miniscore *= (1 - 0.05 * ministat)
      end
      miniscore *= 1.3 if @attacker.moves.any? { |moveloop| moveloop.nil? && moveloop.isHealingMove? }
      miniscore *= 1.3 if @attacker.pbHasMove?(:LEECHSEED)
      miniscore *= 1.2 if @attacker.pbHasMove?(:PAINSPLIT)
      miniscore *= 1.2 if @mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL)
      miniscore *= (1.2 * hpGainPerTurn)
      if @mondata.skill >= MEDIUMSKILL
        miniscore *= 0.3 if checkAIdamage() < 0.12 * @attacker.hp && (getAIMemory().length > 0)
      end
    end
    if @attacker.effects[:Confusion] > 0
      if stats[PBStats::ATTACK] != 0 # if move boosts attack
        miniscore *= 0.2
        miniscore *= 0.5 if stats[PBStats::ATTACK] > 1 # using swords dance or shell smash while confused is Extra Bad
        miniscore *= 1.5 if stats[PBStats::DEFENSE] != 0 # adds a correction for moves that boost attack and defense
      else
        miniscore *= 0.5
      end
    end
    if @battle.doublebattle
      if !(@attacker.pbPartner.pbHasMove?(:PSYCHUP))
        miniscore *= 0.7
      else
        miniscore *= 1.1
      end
      miniscore *= 0.5 if !sweep # drop is doubled
      miniscore *= 1.8 if (@attacker.pbPartner.pbHasMove?(:FOLLOWME) || @attacker.pbPartner.pbHasMove?(:RAGEPOWDER))
    end
    miniscore *= 0.2 if checkAImoves([:CLEARSMOG, :HAZE, :TOPSYTURVY])
    miniscore *= 1.3 if @opponent.effects[:HyperBeam] > 0
    miniscore *= 1.7 if @opponent.effects[:Yawn] > 0
    miniscore *= 2 if @attacker.pbHasMove?(:STOREDPOWER)
    miniscore *= 1.2 if @attacker.pbPartner.pbHasMove?(:PSYCHUP) || @attacker.pbHasMove?(:BATONPASS)

    if move.basedamage > 0
      if @initial_scores[@score_index] >= 100
        miniscore *= 1.2
      elsif @initial_scores.length > 0
        miniscore *= 0.5 if hasgreatmoves()
      end
      miniscore = 1 if @opponent.ability == :UNAWARE || miniscore < 1
      miniscore = pbSereneGraceCheck(miniscore)
    else
      miniscore *= 0 if @attacker.ability == :CONTRARY
      miniscore *= 0.01 if @opponent.ability == :UNAWARE
    end
    return miniscore
  end

  def selfstatdrop(stats,score)
    stats.map!.with_index {|a,ind| @attacker.pbTooLow?(ind+1) ? 0 : a}
    return 1.0 if stats.all? {|a| a==0}
    #Only uses a 5 stat array
    miniscore=1.0
    stats.unshift(0)

    if stats[PBStats::ATTACK] != 0 #Basically just to catch superpower
      if score<100
        miniscore*=0.9
        if !pbAIfaster?()
          miniscore*=1.1
        else
          miniscore*=0.5 if checkAIhealing()
        end
      end
    elsif stats[PBStats::DEFENSE] != 0 || stats[PBStats::SPDEF] != 0
      if score<100
        miniscore*=0.9
        miniscore*=0.9 if stats[PBStats::SPEED] != 0
        if !pbAIfaster?()
          miniscore*=1.1
        else
          miniscore*=0.6 if checkAIhealing()
        end
        miniscore*=0.7 if checkAIpriority()
      end
    elsif stats[PBStats::SPEED] != 0
      miniscore*=0.9 if score<100
      miniscore*=1.1 if @mondata.roles.include?(:TANK)
      if pbAIfaster?()
        miniscore*=0.8
        if @battle.pbPokemonCount(@battle.pbParty(@opponent.index))>1 && @battle.pbPokemonCount(@battle.pbPartySingleOwner(@attacker.index))==1
          miniscore*=0.8
        end
      else
        #miniscore*=1.1
      end
    elsif stats[PBStats::SPATK] != 0
      if @mondata.skill>=BESTSKILL && @battle.FE == :GLITCH && @attacker.getSpecialStat(which_is_higher: true) == PBStats::SPDEF
        miniscore*=1.4
      elsif score<100
        miniscore*=0.9
        miniscore*=0.5 if checkAIhealing()
      end
    end
    if @initial_scores.length>0
      miniscore*=0.6 if hasgreatmoves()
    end
    minimini=100
    livecount=@battle.pbPokemonCount(@battle.pbParty(@opponent.index))
    miniscore*=1 - 0.05 * (livecount-3) if livecount>1

    party=@battle.pbParty(@attacker.index)
    pivotvar=false
    for i in 0...party.length
      next if party[i].nil?
      temproles = pbGetMonRoles(party[i])
      if temproles.include?(:PIVOT)
        pivotvar=true
      end
    end
    miniscore*=1.2 if pivotvar && !@battle.doublebattle
    livecount2=@battle.pbPokemonCount(@battle.pbPartySingleOwner(@attacker.index))
    if livecount>1 && livecount2==1
      miniscore*=0.8
    end
    miniscore = 1 if miniscore < 1 && livecount==1 && score>=100
    return miniscore
  end

  def oppstatboost(stats, confusionmove = false, alsodecrease = false)
    return 0 if @opponent.effects[:Substitute] > 0

    stats.map!.with_index { |a, ind| @opponent.pbTooHigh?(ind + 1) ? 0 : a }
    # This still uses the 5-array of stats in case other games want to expand on it
    stats.unshift(0)
    miniscore = 1.0
    if @opponent.index != @attacker.pbPartner.index
      if @opponent.pbCanConfuse?(false, inflictor: @attacker) && confusionmove
        if stats[PBStats::SPATK] != 0
          miniscore *= 1 + 0.1 * @opponent.stages[PBStats::ATTACK] if @opponent.stages[PBStats::ATTACK] > 0
          if @opponent.attack > @opponent.spatk
            miniscore *= 1.5
          else
            miniscore *= 0.3
          end
        elsif stats[PBStats::ATTACK] != 0
          if @opponent.attack < @opponent.spatk
            miniscore *= 1.5
          else
            miniscore *= 0.7
          end
        end
        miniscore *= confucode
      else
        # for when a move also decreases a stat avoid 0 for multiplication purposes.
        miniscore = alsodecrease ? 1 : 0
      end
      # Gen 9 Mod - Opportunist and Mirror Herb
      if @attacker.ability == :OPPORTUNIST || @attacker.pbPartner.ability == :OPPORTUNIST || @attacker.item == :MIRRORHERB || @attacker.pbPartner.item == :MIRRORHERB
        if miniscore == 0
          miniscore = 1.5
        else
          miniscore *= 1.5
        end
      end
    else
      return 0 if @battle.pbOwnedByPlayer?(@attacker.pbPartner.index)

      if confusionmove
        miniscore *= @opponent.pbCanConfuse?(false, inflictor: @attacker) ? 0.5 : 1.5
        miniscore *= 1.5 if (@opponent.attack < @opponent.spatk && stats[PBStats::ATTACK] != 0) || (@opponent.attack > @opponent.spatk && stats[PBStats::SPATK] != 0)
        miniscore *= 1.2 if @mondata.oppitemworks && (@opponent.item == :PERSIMBERRY || @opponent.item == :LUMBERRY)
      end
      miniscore *= 0.3 if (1.0 / @opponent.totalhp) * @opponent.hp < 0.6
      # Gen 9 Mod - Opportunist
      miniscore *= 0.3 if @opponent.ability == :OPPORTUNIST || @opponent.pbPartner.ability == :OPPORTUNIST || @opponent.item == :MIRRORHERB || @opponent.pbPartner.item == :MIRRORHERB
      if @opponent.effects[:Attract]>=0 || @opponent.status== :PARALYSIS || @opponent.effects[:Yawn]>0 || @opponent.status== :SLEEP
        miniscore *= 0.3
      end
      opp1 = @attacker.pbOppositeOpposing
      opp2 = opp1.pbPartner
      if @opponent.pbSpeed > opp1.pbSpeed && @opponent.pbSpeed > opp2.pbSpeed
        miniscore *= 1.3
      else
        miniscore *= 0.7
      end
    end
    return miniscore
  end

  def oppstatdrop(stats)
    return 1 if @move.basedamage > 0 && @initial_scores[@score_index]>=100
    # Gen 9 Mod - Discourage status moves when current opponent has Good as Gold, but not when abilities are nullified because other abilities.
    return @move.basedamage > 0 ? 1 : 0 if (@opponent.ability == :CLEARBODY || @opponent.ability == :WHITESMOKE || @opponent.ability == :GOODASGOLD) && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))
    # Gen 9 Mod - Added Clear Amulet
    return @move.basedamage > 0 ? 1 : 0 if @opponent.item == :CLEARAMULET
    #stats should be an array of the stat boosts like so: [ATK,DEF,SPE,SPA,SPD,ACC,EVA] with nils in unaffected stats
    #coil, for example, would be [1,1,0,0,0,1,0]
    stats.unshift(0) #this is required to make the next line work correctly
    #Start by eliminating pointless stats
    for i in 1...stats.length
      next if stats[i] == 0
      stats[i] = 0 if !@opponent.pbCanReduceStatStage?(i)
      #Don't get into counter-setup wars you can't win - Ame
      #TODO: probably best to refactor conditions for this, maybe check movememory for setup moves - Fal
      stats[i] = 0 if @move.basedamage == 0 && stats[i] && @opponent.stages[i]>stats[i]
    end
    if stats[PBStats::DEFENSE]>0 || stats[PBStats::SPDEF]>0
      for j in @attacker.moves
        next if j.nil?
        specmove=true if j.pbIsSpecial?()
        physmove=true if j.pbIsPhysical?()
      end
      stats[PBStats::DEFENSE] = 0 if !physmove
      stats[PBStats::SPDEF] = 0 if !specmove
    end
    if stats[PBStats::ATTACK]>0 || stats[PBStats::SPATK]>0
      bestmove = checkAIbestMove()
      stats[PBStats::SPATK] = 0 if (pbRoughStat(@opponent,PBStats::ATTACK)*0.9>pbRoughStat(@opponent,PBStats::SPATK)) && bestmove.pbIsPhysical?()
      stats[PBStats::ATTACK] = 0 if (pbRoughStat(@opponent,PBStats::SPATK)*0.9>pbRoughStat(@opponent,PBStats::ATTACK)) && bestmove.pbIsSpecial?()
    end
    if stats[PBStats::SPEED] > 0
      stats[PBStats::SPEED] = 0 if pbAIfaster?() && @battle.trickroom == 0
      stats[PBStats::SPEED] = 0 if @battle.trickroom > 1
    end
    if stats.all? {|a| a.nil? || a==0 }
      return @move.basedamage > 0 ? 1 : 0
    end
    #This section is split up a little weird to avoid duplicating checks
    miniscore = 1.0
    if @move.basedamage == 0
      statsboosted = 0
      for i in 1...stats.length
        statsboosted += stats[i]
      end
      miniscore = statsboosted
    end
    if stats[PBStats::DEFENSE]>0 || stats[PBStats::SPDEF]>0    #defense stuff
      miniscore*=1.1
      miniscore*=1.2 if checkAIdamage() < @opponent.hp
      miniscore*=1.5 if @move.function == 0x4C
    else      #non-defense stuff
      if @mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL)
        miniscore*=1.3 if stats[PBStats::ATTACK]>0 || stats[PBStats::SPATK]>0 || stats[PBStats::ACCURACY]>0
        miniscore*=1.1 if stats[PBStats::SPEED]>0
      end
    end
    if stats[PBStats::SPEED]>0  #speed stuff
      if (pbRoughStat(@opponent,PBStats::SPEED)*0.66) > @attacker.pbSpeed
        miniscore*= hasgreatmoves() ? 1 : 1.5
      end
      miniscore*=1+0.05*@opponent.stages[PBStats::SPEED] if @opponent.stages[PBStats::SPEED]<0 && !secondaryEffectNegated?()
      miniscore*=0.1 if @opponent.itemWorks? && (@opponent.item == :LAGGINGTAIL || @opponent.item == :IRONBALL)
      miniscore*=0.2 if (@opponent.ability == :COMPETITIVE && !(Rejuv && @battle.FE == :CHESS)) || @opponent.ability == :DEFIANT || @opponent.ability == :CONTRARY
    else    #non-speed stuff
      miniscore*=0.1 if (@opponent.ability == :COMPETITIVE && !(Rejuv && @battle.FE == :CHESS)) || @opponent.ability == :DEFIANT || @opponent.ability == :CONTRARY
      miniscore*=1.1 if @mondata.partyroles.any? {|roles| roles.include?(:SWEEPER)}
    end
    #status & moves section
    if stats[PBStats::DEFENSE]>0 || stats[PBStats::SPATK]>0 || stats[PBStats::SPDEF]>0
      miniscore*=1.2 if @opponent.status== :POISON || @opponent.status== :BURN
    end
    if stats[PBStats::ATTACK]>0
      miniscore*=1.2 if @opponent.status== :POISON
      miniscore*=0.5 if @opponent.status== :BURN
      miniscore*=0.5 if @attacker.pbHasMove?(:FOULPLAY)
    end
    if stats[PBStats::SPEED]>0
      miniscore*=0.5 if @attacker.pbHasMove?(:GYROBALL)
      miniscore*=1.5 if @attacker.pbHasMove?(:ELECTROBALL)
      miniscore*=1.3 if checkAImoves([:ELECTROBALL])
      miniscore*=1.5 if @attacker.crested == :ARIADOS && @opponent.stages[PBStats::SPEED] > -1
      miniscore*=0.5 if checkAImoves([:GYROBALL])
      miniscore*=0.1 if  @battle.trickroom!=0 || checkAImoves([:TRICKROOM])
    end
    if @battle.pbPokemonCount(@battle.pbParty(@opponent.index))==1 || PBStuff::TRAPPINGABILITIESAI.include?(@attacker.ability) || (@attacker.ability == :MAGNETPULL && @opponent.hasType?(:STEEL)) || @opponent.effects[:MeanLook]>0
      miniscore*=1.2
    end
    miniscore *= 0.5 if @mondata.roles.include?(:PHAZER)
    miniscore *= 0.8 if hasgreatmoves() #hoping this doesn't self sabotage
    if move.basedamage>0
      miniscore=pbSereneGraceCheck(miniscore)
    else
      miniscore*=0.5 if @battle.pbPokemonCount(@battle.pbParty(@attacker.index))==1
      miniscore*=0.7 if !@attacker.status.nil?
    end
    return miniscore
  end

  def focusenergycode
    return 0 if @attacker.effects[:FocusEnergy]!=2
    miniscore = 1.0
    attackerHPpercent = (@attacker.hp.to_f)/@attacker.totalhp
    if attackerHPpercent>0.75
      miniscore*=1.2
    elsif attackerHPpercent > 0.5 && attackerHPpercent < 0.75 && (@attacker.ability == :EMERGENCYEXIT || @attacker.ability == :WIMPOUT || (@attacker.itemWorks? && @attacker.item == :EJECTBUTTON))
      miniscore*=0.3
    elsif attackerHPpercent < 0.33
      miniscore*=0.3
    end
    miniscore*=1.3 if @opponent.effects[:HyperBeam]>0
    miniscore*=1.7 if @opponent.effects[:Yawn]>0
    miniscore*=0.6 if @attacker.effects[:LeechSeed]>=0 || @attacker.effects[:Attract]>=0
    miniscore*=0.5 if checkAImoves(PBStuff::PHASEMOVE)
    miniscore*=0.2 if @attacker.effects[:Confusion]>0
    miniscore*=0.3 if @attacker.pbOpposingSide.effects[:Retaliate]
    miniscore*=1.2 if (@attacker.hp/4.0)>checkAIdamage()
    miniscore*=1.2 if @attacker.turncount<2
    miniscore*=1.2 if !@opponent.status.nil?
    miniscore*=1.3 if @opponent.status== :SLEEP || (@opponent.status== :FROZEN && !KAIZOMOD)
    miniscore*=1.5 if @opponent.effects[:Encore]>0 && @opponent.moves[(@opponent.effects[:EncoreIndex])].basedamage==0
    miniscore*=0.5 if @battle.doublebattle
    miniscore*=2 if @attacker.ability == :SUPERLUCK || @attacker.ability == :SNIPER
    miniscore*=1.2 if @mondata.attitemworks && (@attacker.item == :SCOPELENS || @attacker.item == :RAZORCLAW || (@attacker.item == :STICK && @attacker.pokemon.species==:FARFETCHD) || (@attacker.item == :LUCKYPUNCH && @attacker.pokemon.species==:CHANSEY))
    miniscore*=1.3 if (@mondata.attitemworks && @attacker.item == :LANSATBERRY)
    miniscore*=0.2 if @opponent.ability == :ANGERPOINT || @opponent.ability == :SHELLARMOR || @opponent.ability == :BATTLEARMOR
    miniscore*=0.5 if @attacker.pbHasMove?(:LASERFOCUS) || @attacker.pbHasMove?(:FROSTBREATH) || @attacker.pbHasMove?(:STORMTHROW)
    miniscore*= 2**(@attacker.moves.count{|moveloop| moveloop!=nil && moveloop.highCritRate?})
    return miniscore
  end

  def defogcode
    miniscore = 1.0
    yourpartycount = @battle.pbPokemonCount(@battle.pbPartySingleOwner(@attacker.index))
    theirpartycount = @battle.pbPokemonCount(@battle.pbPartySingleOwner(@opponent.index))
    if yourpartycount>1
      miniscore*=2 if @attacker.pbOwnSide.effects[:StealthRock]
      miniscore*=3 if @attacker.pbOwnSide.effects[:StickyWeb]
      miniscore*=(1.5**@attacker.pbOwnSide.effects[:Spikes])
      miniscore*=(1.7**@attacker.pbOwnSide.effects[:ToxicSpikes])
    end
    miniscore -= 1.0
    miniscore*=(yourpartycount-1) if yourpartycount>1
    minimini = 1.0
    if theirpartycount>1
      minimini*=0.5 if @opponent.pbOwnSide.effects[:StealthRock]
      minimini*=0.3 if @opponent.pbOwnSide.effects[:StickyWeb]
      minimini*=(0.7**@opponent.pbOwnSide.effects[:Spikes])
      minimini*=(0.6**@opponent.pbOwnSide.effects[:ToxicSpikes])
    end
    minimini -= 1.0
    minimini*=(theirpartycount-1) if theirpartycount>1
    miniscore+=minimini
    miniscore+=1.0
    if miniscore<0
      miniscore=0
    end
    miniscore*=2 if @opponent.pbOwnSide.effects[:Reflect]>0
    miniscore*=2 if @opponent.pbOwnSide.effects[:LightScreen]>0
    miniscore*=1.3 if @opponent.pbOwnSide.effects[:Safeguard]>0
    miniscore*=3 if @opponent.pbOwnSide.effects[:AuroraVeil]>0
    miniscore*=1.3 if @opponent.pbOwnSide.effects[:Mist]>0
    if @move == :COURTCHANGE
      miniscore*=3 if @opponent.pbOwnSide.effects[:Tailwind]>0

      miniscore*=0.5 if @attacker.pbOwnSide.effects[:Reflect]>0
      miniscore*=0.5 if @attacker.pbOwnSide.effects[:LightScreen]>0
      miniscore*=0.7 if @attacker.pbOwnSide.effects[:Safeguard]>0
      miniscore*=0.3 if @attacker.pbOwnSide.effects[:AuroraVeil]>0
      miniscore*=0.7 if @attacker.pbOwnSide.effects[:Mist]>0
      miniscore*=0.2 if @attacker.pbOwnSide.effects[:Tailwind]>0
    end
    return miniscore
  end

  def volcanoeruptioncode
    return 1 if @battle.eruption
    miniscore = 1.0
    if PBTypes.twoTypeEff(:FIRE,@attacker.type1,@attacker.type2) == 0 || [:MAGMAARMOR,:FLASHFIRE,:FLAREBOOST,:BLAZE,:FLAMEBODY,:SOLIDROCK,:STURDY,:BATTLEARMOR,:SHELLARMOR,:WATERBUBBLE,:MAGICGUARD,:WONDERGUARD,:PRISMARMOR].include?(@attacker.ability) || @attacker.effects[:AquaRing]
      miniscore*=1.0
    elsif PBTypes.twoTypeEff(:FIRE,@attacker.type1,@attacker.type2) == 1
      miniscore*=0.9
    elsif PBTypes.twoTypeEff(:FIRE,@attacker.type1,@attacker.type2) > 2
      miniscore*=0.75
    end
    if !@attacker.pbPartner.pokemon.nil?
      if PBTypes.twoTypeEff(:FIRE,@attacker.pbPartner.type1,@attacker.pbPartner.type2) == 0 || [:MAGMAARMOR,:FLASHFIRE,:FLAREBOOST,:BLAZE,:FLAMEBODY,:SOLIDROCK,:STURDY,:BATTLEARMOR,:SHELLARMOR,:WATERBUBBLE,:MAGICGUARD,:WONDERGUARD,:PRISMARMOR].include?(@attacker.pbPartner.ability) || @attacker.pbPartner.effects[:AquaRing]
        miniscore*=1.0
      elsif PBTypes.twoTypeEff(:FIRE,@attacker.pbPartner.type1,@attacker.pbPartner.type2) == 1
        miniscore*=0.9
      elsif PBTypes.twoTypeEff(:FIRE,@attacker.pbPartner.type1,@attacker.pbPartner.type2) > 2
        miniscore*=0.75
      end
    end
    miniscore*=1.2 if PBTypes.twoTypeEff(:FIRE,@opponent.type1,@opponent.type2) > 2
    if !@opponent.pbPartner.pokemon.nil?
      miniscore*=1.2 if PBTypes.twoTypeEff(:FIRE,@opponent.pbPartner.type1,@opponent.pbPartner.type2) > 2
    end
    miniscore*=1.5 if (@attacker.ability == :FLASHFIRE && !@attacker.effects[:FlashFire])
    miniscore*=1.5 if (@attacker.pbPartner.ability == :FLASHFIRE && !@attacker.pbPartner.effects[:FlashFire])
    miniscore*=1.5 if (@attacker.ability == :BLAZE && !@attacker.effects[:Blazed])
    miniscore*=1.5 if (@attacker.pbPartner.ability == :BLAZE && !@attacker.pbPartner.effects[:Blazed])
    miniscore*=1.3 if @attacker.ability == :FLAREBOOST
    miniscore*=1.3 if @attacker.pbPartner.ability == :FLAREBOOST
    miniscore*=1.75 if @attacker.ability == :MAGMAARMOR
    miniscore*=1.75 if @attacker.pbPartner.ability == :MAGMAARMOR
    miniscore*=0.5 if (@opponent.ability == :FLASHFIRE && !@opponent.effects[:FlashFire])
    miniscore*=0.5 if (@opponent.pbPartner.ability == :FLASHFIRE && !@opponent.pbPartner.effects[:FlashFire])
    miniscore*=0.5 if (@opponent.ability == :BLAZE && !@opponent.effects[:Blazed])
    miniscore*=0.5 if (@opponent.pbPartner.ability == :BLAZE && !@opponent.pbPartner.effects[:Blazed])
    miniscore*=0.75 if @opponent.ability == :FLAREBOOST
    miniscore*=0.75 if @opponent.pbPartner.ability == :FLAREBOOST
    miniscore*=0.2 if @opponent.ability == :MAGMAARMOR
    miniscore*=0.2 if @opponent.pbPartner.ability == :MAGMAARMOR
    miniscore*=1.3 if @attacker.effects[:LeechSeed]>=0
    miniscore*=1.3 if @attacker.pbPartner.effects[:LeechSeed]>=0
    miniscore*=0.8 if @opponent.effects[:LeechSeed]>=0
    miniscore*=0.8 if @opponent.pbPartner.effects[:LeechSeed]>=0
    yourpartycount = @battle.pbPokemonCount(@battle.pbPartySingleOwner(@attacker.index))
    theirpartycount = @battle.pbPokemonCount(@battle.pbPartySingleOwner(@opponent.index))
    minimini1 = 1.0
    if yourpartycount>1
      minimini1*=1.5 if @attacker.pbOwnSide.effects[:StealthRock]
      minimini1*=2 if @attacker.pbOwnSide.effects[:StickyWeb]
      minimini1*=(1.3**@attacker.pbOwnSide.effects[:Spikes])
      minimini1*=(1.5**@attacker.pbOwnSide.effects[:ToxicSpikes])
    end
    minimini1 = -1.0
    minimini1*=(yourpartycount-1) if yourpartycount>1
    minimini2 = 1.0
    if theirpartycount>1
      minimini2*=0.75 if @opponent.pbOwnSide.effects[:StealthRock]
      minimini2*=0.5 if @opponent.pbOwnSide.effects[:StickyWeb]
      minimini2*=(0.9**@opponent.pbOwnSide.effects[:Spikes])
      minimini2*=(0.85**@opponent.pbOwnSide.effects[:ToxicSpikes])
    end
    minimini2 -= 1.0
    minimini2*=(theirpartycount-1) if theirpartycount>1
    subscore=(minimini1+minimini2+1.0)
    if subscore<0.5
      subscore=0.5
    end
    miniscore *= subscore
    return miniscore
  end

  def oppstatrestorecode
    return 1 if @opponent.effects[:Substitute] > 0
    miniscore = 1 + 0.05*statchangecounter(@opponent,1,7)
    miniscore *=1.1 if (@opponent.ability == :SPEEDBOOST || (@opponent.ability == :MOTORDRIVE && @battle.FE == :ELECTERRAIN) || (@opponent.ability == :STEAMENGINE && [:UNDERWATER,:WATERSURFACE,:VOLCANIC,:VOLCANICTOP,:INFERNAL].include?(@battle.FE)))
    return miniscore
  end

  def hazecode
    oppscore = 1.1 * statchangecounter(@opponent,1,7)
    attscore = -1.1 * statchangecounter(@attacker,1,7)
    if @battle.doublebattle
      oppscore += 1.1 * statchangecounter(@opponent.pbPartner,1,7) if @opponent.pbPartner.hp>0
      attscore += -1.1 * statchangecounter(@attacker.pbPartner,1,7) if @attacker.pbPartner.hp>0
    end
    miniscore = oppscore + attscore
    miniscore*=0.8 if ((@opponent.ability == :SPEEDBOOST || (@opponent.ability == :MOTORDRIVE && @battle.FE == :ELECTERRAIN) || (@opponent.ability == :STEAMENGINE && [:UNDERWATER,:WATERSURFACE,:VOLCANIC,:VOLCANICTOP,:INFERNAL].include?(@battle.FE))) || checkAImoves(PBStuff::SETUPMOVE))
    return miniscore
  end

  def statswapcode(stat1,stat2)
    attstages = @attacker.stages[stat1] + @attacker.stages[stat2]
    miniscore = -1.1 * attstages
    if (pbRoughStat(@attacker,stat1)>pbRoughStat(@attacker,stat2))
      miniscore*=2 if @attacker.stages[stat1]<0
    else
      miniscore*=2 if @attacker.stages[stat2]<0
    end
    oppstages = @opponent.stages[stat1] + @opponent.stages[stat2]
    minimini = -1.1 * attstages
    if (pbRoughStat(@opponent,stat1)>pbRoughStat(@opponent,stat2))
      minimini*=2 if @opponent.stages[stat1]>0
    else
      minimini*=2 if @opponent.stages[stat2]>0
    end
    miniscore+=minimini
    miniscore*=0.8 if @battle.doublebattle
    return miniscore
  end

  def psychupcode
    statarray = [0,0,0,0,0,0,0]
    boostarray = [0,0,0,0,0,0,0]
    droparray = [0,0,0,0,0,0,0]
    statarray[0] = (@opponent.stages[PBStats::ATTACK]-@attacker.stages[PBStats::ATTACK])
    statarray[1] = (@opponent.stages[PBStats::DEFENSE]-@attacker.stages[PBStats::DEFENSE])
    statarray[2] = (@opponent.stages[PBStats::SPATK]-@attacker.stages[PBStats::SPATK])
    statarray[3] = (@opponent.stages[PBStats::SPDEF]-@attacker.stages[PBStats::SPDEF])
    statarray[4] = (@opponent.stages[PBStats::SPEED]-@attacker.stages[PBStats::SPEED])
    statarray[5] = (@opponent.stages[PBStats::ACCURACY]-@attacker.stages[PBStats::ACCURACY])
    statarray[6] = (@opponent.stages[PBStats::EVASION]-@attacker.stages[PBStats::EVASION])
    for i in 0..6
      boostarray[i] = statarray[i] if i > 0
      droparray[i] = statarray[i]*-1 if i < 0
    end
    return boostarray,droparray
  end

  def mistcode
    miniscore = 1.0
    if @attacker.pbOwnSide.effects[:Mist]==0
      miniscore*=1.1
      # check opponent for stat decreasing moves
      miniscore*=1.3 if getAIMemory().any? {|j| j.function==0x42 || j.function==0x43 || j.function==0x44 || j.function==0x45 || j.function==0x46 || j.function==0x47 || j.function==0x48 || j.function==0x49 || j.function==0x4A || j.function==0x4B || j.function==0x4C || j.function==0x4D || j.function==0x4E || j.function==0x4F || j.function==0xE2 || j.function==0x138 || j.function==0x13B || j.function==0x13F}
    end
    return miniscore
  end

  def powertrickcode
    miniscore=1.0
    if @attacker.attack - @attacker.defense >= 100
      miniscore*=1.5 if pbAIfaster?(@move)
      miniscore*=2 if pbRoughStat(@opponent,PBStats::ATTACK)>pbRoughStat(@opponent,PBStats::SPATK)
      miniscore*=2 if @attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.isHealingMove?}
    elsif @attacker.defense - @attacker.attack >= 100
      if pbAIfaster?(@move)
        miniscore*=1.5
        miniscore*=2 if notOHKO?(@attacker, @opponent)
      else
        miniscore*=0
      end
    else
      miniscore*=0.1
    end
    miniscore*=0.1 if @attacker.effects[:PowerTrick]
    return miniscore
  end

  def splitcode(stat)
    return 0 if @opponent.effects[:Substitute] > 0
    miniscore=1.0
    case stat
      when PBStats::ATTACK
        if @opponent.attack > @opponent.spatk
          return 0 if @attacker.attack > @opponent.attack
          miniscore = @opponent.attack - @attacker.attack
          miniscore *= @attacker.attack > @attacker.spatk ? 2 : 0.5
        else
          return 0 if @attacker.spatk > @opponent.spatk
          miniscore = @opponent.spatk - @attacker.spatk
          miniscore *= @attacker.spatk > @attacker.attack ? 2 : 0.5
        end
      when PBStats::DEFENSE
        if @opponent.attack > @opponent.spatk
          return 0 if @attacker.defense > @opponent.defense
          miniscore = @opponent.defense - @attacker.defense
          miniscore *= @attacker.attack > @attacker.spatk ? 2 : 0.5
        else
          return 0 if @attacker.spdef > @opponent.spdef
          miniscore = @opponent.spdef - @attacker.spdef
          miniscore *= @attacker.spatk > @attacker.attack ? 2 : 0.5
        end
      when PBStats::HP
        ministat = [(@opponent.hp + @attacker.hp) / 2.0, @attacker.totalhp].min
        return 0 if ministat < @attacker.hp && pbAIfaster?(@move)
        maxdam = checkAIdamage()
        return 0 if @opponent.hp <= (@attacker.hp - maxdam)
        return 0 if maxdam > ministat
        if maxdam > @attacker.hp
          return pbAIfaster?(@move) ? 2 : 0
        else
          miniscore *= 0.3 if checkAImoves(PBStuff::SETUPMOVE)
          miniscore *= @opponent.hp / (@attacker.hp).to_f
          return miniscore
        end
    end
    miniscore = 1 + miniscore / 100.0
    return miniscore
  end

  def tailwindcode
    return 0 if @attacker.pbOwnSide.effects[:Tailwind] > 0

    miniscore = 1.5
    if pbAIfaster?() && !@mondata.roles.include?(:LEAD)
      miniscore *= 0.9
      miniscore *= 0.4 if @attacker.pbNonActivePokemonCount == 0
    end
    miniscore *= 0.5 if (
      @opponent.ability == :SPEEDBOOST || (@opponent.ability == :MOTORDRIVE && @battle.FE == :ELECTERRAIN) ||
      (@opponent.ability == :STEAMENGINE && [:UNDERWATER, :WATERSURFACE, :VOLCANIC, :VOLCANICTOP, :INFERNAL].include?(@battle.FE))
    )
    miniscore *= 0.1 if @battle.trickroom != 0 || checkAImovesAllOpponents([:TRICKROOM])
    miniscore *= 1.4 if @mondata.roles.include?(:LEAD)
    miniscore *= 2.5 if !@battle.opponent.nil? && !@battle.opponent.is_a?(Array) && @battle.opponent.trainertype == :ADRIENN
    miniscore *= 0.3 if checkAImovesAllOpponents([:SNATCH])
    return miniscore
  end

  def mimicsketchcode(blacklist,sketch)
    lastmove = (sketch) ? @opponent.lastMoveUsedSketch : @opponent.lastMoveUsed
    return 0 if lastmove == -1
    return 0 if @opponent.effects[:Substitute] > 0
    return 0 if pbAIfaster?(@move) && (blacklist.include?($cache.moves[lastmove].function) || lastmove.is_a?(Symbol))
    miniscore = ($cache.moves[lastmove].basedamage > 0) ? $cache.moves[lastmove].basedamage : 40
    miniscore=1 + miniscore/100.0
    miniscore*=0.5 if miniscore<=1.5
    miniscore*=0.5 if !pbAIfaster?(@move)
    return miniscore
  end

  def typechangecode(type)
    type = type.intern if !type.is_a?(Symbol)
    return 0 if type == @attacker.type1 && @attacker.type2.nil?
    return 0 if @attacker.ability == :MULTITYPE || @attacker.ability == :RKSSYSTEM || @attacker.crested == :SILVALLY || @attacker.ability == :PROTEAN || @attacker.ability == :LIBERO || @attacker.ability == :COLORCHANGE || (@attacker.ability == :DOWNLOAD && @battle.FE == :DIMENSIONAL)
    miniscore = [PBTypes.twoTypeEff(@opponent.type1,@attacker.type1,@attacker.type2),PBTypes.twoTypeEff(@opponent.type2,@attacker.type1,@attacker.type2)].max
    minimini = [@opponent.type1.nil? ? 0 : PBTypes.oneTypeEff(@opponent.type1,type), @opponent.type2.nil? ? 0 : PBTypes.oneTypeEff(@opponent.type2,type)].max
    return 0 if minimini > miniscore
    miniscore*=2
    miniscore*=pbAIfaster?(@move) ? 1.2 : 0.7
    stabvar = false
    newstabvar = false
    for i in @attacker.moves
      next if i.nil?
      stabvar = true if (i.pbType(@attacker)==@attacker.type1 || i.pbType(@attacker)==@attacker.type2) && i.basedamage != 0
      newstabvar = true if i.pbType(@attacker)==type && i.basedamage != 0
    end
    if stabvar && !newstabvar
      miniscore*=1.2
    else
      miniscore*=0.6
    end
    return miniscore
  end

  def opptypechangecode(type)
    return 0 if type == @opponent.type1 && @opponent.type2.nil?
    # Gen 9 Mod - Added Ogerpon forms 8 or higher since Terastalized Ogerpon's type cannot be changed.
    # Gen 9 Mod - Added Terapagos form 2 since Terastalized Terapagos's type cannot be changed.
    return 0 if @opponent.ability == :MULTITYPE || @opponent.ability == :RKSSYSTEM || @attacker.crested == :SILVALLY || @opponent.ability == :PROTEAN || @opponent.ability == :LIBERO || @opponent.ability == :COLORCHANGE || (@opponent.ability == :DOWNLOAD && @battle.FE == :DIMENSIONAL) || (@opponent.species == :OGERPON && @opponent.form >= 8) || (@opponent.species == :TERAPAGOS && @opponent.form == 2)
    miniscore = [PBTypes.twoTypeEff(@attacker.type1,@opponent.type1,@opponent.type2),PBTypes.twoTypeEff(@attacker.type2,@opponent.type1,@opponent.type2)].max
    minimini = [PBTypes.oneTypeEff(@attacker.type1,type),PBTypes.oneTypeEff(@attacker.type2,type)].max
    if !(@move.function == 0x205)
      return 0 if minimini < miniscore
      minimini *= 0.5 if getAIMemory(@opponent).any?{|moveloop|moveloop!=nil && moveloop.pbType(@opponent) == type}
    end
    minimini *= 1.5 if @attacker.moves.any?{|moveloop| moveloop!=nil && PBTypes.oneTypeEff(moveloop.pbType(@attacker),type) > 2}
    return minimini
  end

  def abilitychangecode(ability)
    return 0 if @opponent.ability == ability || (PBStuff::FIXEDABILITIES).include?(@opponent.ability)
    # Gen 9 Mod - Added Ability Shield
    return 0 if (@mondata.oppitemworks && @opponent.item == :ABILITYSHIELD)
    miniscore = getAbilityDisruptScore(@attacker,@opponent)
    if @opponent.index == @attacker.pbPartner.index
      if miniscore < 2
          miniscore = 2 - miniscore
      else
          miniscore = 0
      end
    end
    if ability == :SIMPLE
      miniscore*=1.3 if @opponent.index==@attacker.pbPartner.index && @opponent.moves.any?{|moveloop| moveloop!=nil && (PBStuff::SETUPMOVE).include?(moveloop)}
      miniscore*=0.5 if checkAImoves(PBStuff::SETUPMOVE)
    elsif ability == :INSOMNIA
      miniscore*=1.3 if checkAImoves([:SNORE,:SLEEPTALK])
      miniscore*=2 if checkAImoves([:REST])
      miniscore*=0.3 if @attacker.moves.any?{|moveloop| moveloop!=nil && (PBStuff::SLEEPMOVE).include?(moveloop)}
    end
    return miniscore
  end

  def roleplaycode # Role Play
    return 0 if (PBStuff::ABILITYBLACKLIST).include?(@opponent.ability)
    return 0 if (PBStuff::FIXEDABILITIES).include?(@attacker.ability)
    return 0 if @opponent.ability == 0 || @attacker.ability == @opponent.ability
    # Gen 9 Mod - Added Ability Shield
    return 0 if (@mondata.attitemworks && @attacker.item == :ABILITYSHIELD)
    miniscore = getAbilityDisruptScore(@opponent,@attacker)
    minimini = getAbilityDisruptScore(@attacker,@opponent)
    return (1 + (minimini-miniscore))
  end

  def entraincode(score)
    return 0 if (PBStuff::FIXEDABILITIES).include?(@opponent.ability)
    return 0 if @opponent.ability == :TRUANT
    return 0 if (PBStuff::ABILITYBLACKLIST).include?(@attacker.ability) && @attacker.ability != :WONDERGUARD
    return 0 if @opponent.ability == 0 || @attacker.ability == @opponent.ability
    # Gen 9 Mod - Added Ability Shield
    return 0 if (@mondata.oppitemworks && @opponent.item == :ABILITYSHIELD)
    miniscore = getAbilityDisruptScore(@opponent,@attacker)
    minimini = getAbilityDisruptScore(@attacker,@opponent)
    if @opponent.index != @attacker.pbPartner.index
      score*= (1 + (minimini-miniscore))
      if (@attacker.ability == :TRUANT)
        score*=3
      elsif (@attacker.ability == :WONDERGUARD)
        score=0
      end
    else
      score *= (1 + (miniscore-minimini))
      case @attacker.ability
        when :WONDERGUARD then score +=85
        when :SPEEDBOOST  then score +=25
      end
      case @opponent.ability
        when :DEFEATIST  then score +=30
        when :SLOWSTART  then score +=50
      end
    end
    return score
  end

  def skillswapcode
    return 0 if (PBStuff::FIXEDABILITIES).include?(@attacker.ability) && @attacker.ability != :ZENMODE
    return 0 if (PBStuff::FIXEDABILITIES).include?(@opponent.ability) && @opponent.ability != :ZENMODE
    return 0 if @opponent.ability == :ILLUSION || @attacker.ability == :ILLUSION
    # Gen 9 Mod - Added Poison Puppeteer
    return 0 if @opponent.ability == :POISONPUPPETEER || @attacker.ability == :POISONPUPPETEER
    return 0 if @opponent.ability == 0 || @attacker.ability == @opponent.ability
    # Gen 9 Mod - Added Ability Shield
    return 0 if (@mondata.oppitemworks && @opponent.item == :ABILITYSHIELD)
    return 0 if (@mondata.attitemworks && @attacker.item == :ABILITYSHIELD)
    miniscore = getAbilityDisruptScore(@opponent,@attacker)
    minimini = getAbilityDisruptScore(@attacker,@opponent)
    miniscore = [2-miniscore,0].max if @opponent.index == @attacker.pbPartner.index
    miniscore *= (1 + (minimini-miniscore)*2)
    miniscore*=2 if (@attacker.ability == :TRUANT && @opponent.index!=@attacker.pbPartner.index) || (@opponent.ability == :TRUANT && @opponent.index==@attacker.pbPartner.index)
    return miniscore
  end

  def gastrocode
    return 0 if @opponent.effects[:GastroAcid] || @opponent.effects[:Substitute]>0 || (PBStuff::FIXEDABILITIES).include?(@opponent.ability)
    # Gen 9 Mod - Added Ability Shield
    return 0 if (@mondata.oppitemworks && @opponent.item == :ABILITYSHIELD)
    return getAbilityDisruptScore(@attacker,@opponent)
  end

  def transformcode
    return 0 if @opponent.effects[:Transform] || @opponent.effects[:Illusion] || @opponent.effects[:Substitute]>0 || @attacker.effects[:Transform]
    miniscore = 1 + (@opponent.level - @attacker.level) / 20
    miniscore *= 1.1 * (statchangecounter(@opponent,1,5) - statchangecounter(@attacker,1,5))
    return miniscore
  end

  def endeavorcode
    return 0 if @attacker.hp > @opponent.hp
    miniscore = 1.0
    miniscore*=1.5 if @attacker.moves.any?{|moveloop| moveloop!=nil && moveloop.pbIsPriorityMoveAI(@attacker)}
    miniscore*=1.5 if notOHKO?(@attacker, @opponent, true)
    miniscore*=2 if @opponent.level - @attacker.level > 9
    return miniscore
  end

  def ohkode
    return 0 if (@opponent.level>@attacker.level) || notOHKO?(@opponent, @attacker, true)
    return 3.5 if @opponent.effects[:LockOn]>0 || @opponent.ability==:NOGUARD || @attacker.ability==:NOGUARD || (@attacker.ability==:FAIRYAURA && @battle.FE == :FAIRYTALE)
    return 0.7
  end

  def counterattackcode
    miniscore = 1.0
    maxdam = checkAIdamage()
    miniscore*=0.5 if pbAIfaster?()
    if notOHKO?(@attacker, @opponent, true)
      miniscore*=1.2
    else
      miniscore*=0.8
      miniscore*=0.8 if maxdam>@attacker.hp
    end
    miniscore*=0.7 if !$cache.moves[@attacker.lastMoveUsed].nil? &&
    $cache.moves[@attacker.lastMoveUsed].function == @move.function
    miniscore*=0.6 if checkAImoves(PBStuff::SETUPMOVE)
    miniscore*=(@attacker.hp/@attacker.totalhp)
    bestmove = checkAIbestMove()
    if @move.function == 0x71 # Counter
      if pbRoughStat(@opponent,PBStats::ATTACK) > (pbRoughStat(@opponent,PBStats::SPATK) * 1.1) # attack is at least 10% higher than sp.atk
        miniscore*=1.1
      elsif pbRoughStat(@opponent,PBStats::ATTACK)<(pbRoughStat(@opponent,PBStats::SPATK) * 0.6)
        miniscore*=0.3
      else
        miniscore*=0.6
      end
      miniscore*=0.05 if bestmove.pbIsSpecial?()
      miniscore*=1.1 if !$cache.moves[@attacker.lastMoveUsed].nil? &&
      $cache.moves[@attacker.lastMoveUsed].function==0x72
    elsif @move.function == 0x72 # Mirror Coat
      if (pbRoughStat(@opponent,PBStats::ATTACK) * 1.1)<pbRoughStat(@opponent,PBStats::SPATK) # attack is at least 10% higher than sp.atk
        miniscore*=1.1
      elsif (pbRoughStat(@opponent,PBStats::ATTACK) * 0.6)>pbRoughStat(@opponent,PBStats::SPATK)
        miniscore*=0.3
      else
        miniscore*=0.6
      end
      miniscore*=0.3 if @opponent.spatk<@opponent.attack
      miniscore*=0.05 if bestmove.pbIsPhysical?()
      miniscore*=1.1 if !$cache.moves[@attacker.lastMoveUsed].nil? &&
      $cache.moves[@attacker.lastMoveUsed].function==0x71
    end
    return miniscore
  end

  def revengecode
    miniscore = 1.0
    miniscore*= pbAIfaster?() ? 0.5 : 1.5
    if @attacker.hp==@attacker.totalhp
      miniscore*=1.2
      miniscore*=1.1 if notOHKO?(@attacker, @opponent, true)
    else
      miniscore*=0.3 if checkAIdamage()>@attacker.hp
    end
    miniscore*=0.8 if checkAImoves(PBStuff::SETUPMOVE)
    return miniscore
  end

  def pursuitcode
    miniscore=1-0.1*statchangecounter(@opponent,1,7,-1)
    miniscore*=1.2 if @opponent.effects[:Confusion]>0
    miniscore*=1.5 if @opponent.effects[:LeechSeed]>=0
    miniscore*=1.3 if @opponent.effects[:Attract]>=0
    miniscore*=0.7 if @opponent.effects[:Substitute]>0
    miniscore*=1.5 if @opponent.effects[:Yawn]>0
    miniscore*=1.5 if pbTypeModNoMessages>4
    return miniscore
  end

  def echocode
    miniscore = 1.0
    miniscore*=0.7 if @attacker.status== :PARALYSIS
    miniscore*=0.7 if @attacker.effects[:Confusion]>0
    miniscore*=0.7 if @attacker.effects[:Attract]>=0
    miniscore*=1.3 if @attacker.hp==@attacker.totalhp
    miniscore*=1.5 if checkAIdamage()<(@attacker.hp/3.0)
    return miniscore
  end

  def helpinghandcode
    return 0 if !@battle.doublebattle || @attacker.pbPartner.hp==0
    # Gen 9 Mod - Discourage helping hand when partner has Good as Gold
    return 0 if @attacker.pbPartner.ability == :GOODASGOLD && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))
    miniscore = 1.0
    miniscore*=2 if !@attacker.moves.any?{|moveloop| moveloop!=nil && pbTypeModNoMessages(moveloop.pbType(@attacker),@attacker,@opponent,moveloop,@mondata.skill)>=4}
    if !pbAIfaster?() && !pbAIfaster?(nil,nil,@attacker,@opponent.pbPartner)
      miniscore*=1.2
      miniscore*=1.5 if @attacker.hp/@attacker.totalhp < 0.33
      miniscore*=1.5 if !pbAIfaster?(nil,nil,@attacker.pbPartner,@opponent) && !pbAIfaster?(nil,nil,@attacker.pbPartner,@opponent.pbPartner)
    end
    miniscore *= 1+(([@attacker.pbPartner.attack,@attacker.pbPartner.spatk].max - [@attacker.attack,@attacker.spatk].max) / 100)
    return miniscore
  end

  def mudsportcode
    return 0 if @battle.state.effects[:MudSport] != 0
    miniscore = 1.0
    eff1 = PBTypes.twoTypeEff(:ELECTRIC,@attacker.type1,@attacker.type2)
    eff2 = @attacker.pbPartner.hp >0 ?  PBTypes.twoTypeEff(:ELECTRIC,@attacker.pbPartner.type1,@attacker.pbPartner.type2) : 0
    miniscore*=1.5 if eff1>4 || eff2>4 && @opponent.hasType?(:ELECTRIC)
    miniscore*=0.7 if pbPartyHasType?(:ELECTRIC)
    return miniscore
  end

  def watersportcode
    return 0 if @battle.state.effects[:WaterSport] != 0
    miniscore = 1.0
    eff1 = PBTypes.twoTypeEff(:FIRE,@attacker.type1,@attacker.type2)
    eff2 = @attacker.pbPartner.hp >0 ? PBTypes.twoTypeEff(:FIRE,@attacker.pbPartner.type1,@attacker.pbPartner.type2) : 0
    miniscore*=1.5 if eff1>4 || eff2>4 && @opponent.hasType?(:FIRE)
    miniscore*=0.7 if pbPartyHasType?(:FIRE)
    return miniscore
  end

  def permacritcode(initialscore)
    return 0 if @opponent.index == @attacker.pbPartner.index && (@opponent.ability != :ANGERPOINT || @opponent.stages[PBStats::ATTACK]==6)
    return 0 if @attacker.effects[:LaserFocus]!=0 && @move.function==0x165
    return 0.7 if @opponent.ability == :BATTLEARMOR || @opponent.ability == :SHELLARMOR
    miniscore = 1.0
    miniscore += 0.1 * @opponent.stages[PBStats::DEFENSE] if @opponent.stages[PBStats::DEFENSE]>0
    miniscore += 0.1 * @opponent.stages[PBStats::SPDEF] if @opponent.stages[PBStats::SPDEF]>0
    miniscore -= 0.1 * @attacker.stages[PBStats::ATTACK] if @attacker.stages[PBStats::ATTACK]<0
    miniscore -= 0.1 * @attacker.stages[PBStats::SPATK] if @attacker.stages[PBStats::SPATK]<0
    miniscore -= 0.1 * @attacker.effects[:FocusEnergy] if @attacker.effects[:FocusEnergy]>0
    return miniscore if !(@opponent.ability == :ANGERPOINT && @opponent.stages[PBStats::ATTACK]!=6)
    if @attacker.pbPartner.index == @opponent.index && @move.function != 0x165
      return 0 if @opponent.attack>@opponent.spatk || initialscore>80
      miniscore = (100-initialscore)
      if pbAIfaster?(nil,nil,@opponent,@attacker.pbOpposing2) && pbAIfaster?(nil,nil,@opponent,@attacker.pbOpposing1)
        miniscore*=1.3
      else
          miniscore*=0.7
      end
    else
      if initialscore<100
          miniscore*=0.7
          miniscore*=0.2 if @opponent.attack>@opponent.spatk
      end
    end
    return miniscore
  end

  def screencode
    return 0 if (@attacker.pbOwnSide.effects[:Reflect] > 0 && @move.function == 0xA2) || (@attacker.pbOwnSide.effects[:LightScreen] > 0 && @move.function == 0xA3) || (@attacker.pbOwnSide.effects[:AreniteWall] > 0 && @move.function == 0x203)
    return 0 if @attacker.pbOwnSide.effects[:AuroraVeil] > 0 && (@move.function == 0x15b || @move.function == 0x80C)
    return 0 if @move.function == 0x15b && !(@battle.pbWeather == :HAIL || (@mondata.skill >= BESTSKILL && (@battle.FE == :SNOWYMOUNTAIN || @battle.FE == :MIRROR || @battle.FE == :STARLIGHT || @battle.FE == :DARKCRYSTALCAVERN || @battle.FE == :RAINBOW || @battle.FE == :ICY || @battle.FE == :CRYSTALCAVERN || @battle.FE == :FROZENDIMENSION)))
    return 0 if @move.function == 0x203 && !(@battle.pbWeather == :SANDSTORM || (@mondata.skill >= BESTSKILL && (@battle.FE == :DESERT || @battle.FE == :ASHENBEACH || @battle.FE == :ROCKY)))
    return 0 if @attacker.pbOwnSide.effects[:AuroraVeil] > 3

    miniscore = 1.2
    miniscore *= 0.2 if @attacker.pbOwnSide.effects[:AuroraVeil] > 0 && @move.function != 0x203 # Arenite Wall applies seperately
    if @move.function == 0xA2 # Reflect
      if pbRoughStat(@opponent, PBStats::ATTACK) > (pbRoughStat(@opponent, PBStats::SPATK) * 1.1) # attack is at least 10% higher than sp.atk
        miniscore *= 1.3
      elsif pbRoughStat(@opponent, PBStats::ATTACK) < (pbRoughStat(@opponent, PBStats::SPATK) * 0.6)
        miniscore *= 0.5
      else
        miniscore *= 0.9
      end
    elsif @move.function == 0xA3 # Light Screen
      if (pbRoughStat(@opponent, PBStats::ATTACK) * 1.1) < pbRoughStat(@opponent, PBStats::SPATK) # attack is at least 10% higher than sp.atk
        miniscore *= 1.3
      elsif (pbRoughStat(@opponent, PBStats::ATTACK) * 0.6) > pbRoughStat(@opponent, PBStats::SPATK)
        miniscore *= 0.5
      else
        miniscore *= 0.9
      end
    end
    miniscore *= 1.1 if (@mondata.attitemworks && @attacker.item == :LIGHTCLAY) || @mondata.skill >= BESTSKILL && @battle.FE == :MIRROR
    if pbAIfaster?(@move)
      miniscore *= 1.1
      if @mondata.skill >= MEDIUMSKILL
        if getAIMemory().length > 0
          # patch this to check for physical or special based on function code
          maxdam = 0
          for j in getAIMemory()
            next if @move.function == 0xA2 && !j.pbIsPhysical?()
            next if @move.function == 0xA3 && !j.pbIsSpecial?()

            tempdam = pbRoughDamage(j, @opponent, @attacker)
            maxdam = tempdam if maxdam < tempdam
          end
          miniscore *= 2 if maxdam > @attacker.hp && (maxdam / 2.0) < @attacker.hp
        end
      end
    end
    livecount = @battle.pbPokemonCount(@battle.pbParty(@opponent.index))
    if livecount <= 2
      miniscore *= 0.7
      miniscore *= 0.5 if livecount == 1
    else
      miniscore *= 1.4 if (@mondata.attitemworks && @attacker.item == :LIGHTCLAY)
    end
    miniscore *= 1.3 if notOHKO?(@attacker, @opponent)
    if @attacker.index == 2 # for partners to guess if the player will use aurora veil
      miniscore *= 0.3 if @attacker.pbPartner.pbHasMove?(:AURORAVEIL) if @move.function != 0x203
      if @move.function == 0xA2 # Reflect
        miniscore *= 0.3 if @attacker.pbPartner.pbHasMove?(:REFLECT)
      elsif @move.function == 0xA3 # Light Screen
        miniscore *= 0.3 if @attacker.pbPartner.pbHasMove?(:LIGHTSCREEN)
      elsif @move.function == 0x203 # Arenite Wall
        miniscore *= 0.3 if @attacker.pbPartner.pbHasMove?(:ARENITEWALL)
      end
    end
    miniscore *= 0.1 if checkAImovesAllOpponents(PBStuff::SCREENBREAKERMOVE)
    miniscore *= 0.3 if checkAImovesAllOpponents([:SNATCH])
    return miniscore
  end

  def secretcode
    case @battle.FE
      when :ELECTERRAIN,:SHORTCIRCUIT              then return paracode()
      when :GRASSY,:FOREST,:FAIRYTALE              then return sleepcode()
      when :MISTY,:HOLY                     then return oppstatdrop([0,0,1,0,0,0,0])
      when :DARKCRYSTALCAVERN,:DESERT,:ASHENBEACH,:CLOUDS    then return oppstatdrop([0,0,0,0,0,1,0])
      when :CHESS, :DARKNESS1, :DARKNESS2, :DARKNESS3      then return oppstatdrop([0,1,0,0,0,0,0])
      when :BIGTOP,:STARLIGHT                 then return oppstatdrop([0,0,0,1,0,0,0])
      when :BURNING,:SUPERHEATED,:DRAGONSDEN,:VOLCANIC,:VOLCANICTOP,:INFERNAL,:DANCEFLOOR   then return burncode()
      when :SWAMP,:WATERSURFACE,:GLITCH             then return oppstatdrop([0,0,0,0,1,0,0])
      when :RAINBOW                      then return (paracode() + poisoncode() + burncode() + (KAIZOMOD ? frostbitecode() : freezecode()) + sleepcode()) / 5
      when :CORROSIVE,:CORROSIVEMIST,:MURKWATERSURFACE,:CORRUPTED,:BACKALLEY,:CITY   then return poisoncode()
      when :ICY,:SNOWYMOUNTAIN,:FROZENDIMENSION         then return (KAIZOMOD ? frostbitecode() : freezecode())
      when :ROCKY,:CAVE,:MOUNTAIN,:DIMENSIONAL,:DEEPEARTH,:CONCERT1,:CONCERT2,:CONCERT3,:CONCERT4   then return flinchcode()
      when :FACTORY,:UNDERWATER                 then return oppstatdrop([1,0,0,0,0,0,0])
      when :WASTELAND                     then return (paracode() + poisoncode() + burncode() + (KAIZOMOD ? frostbitecode() : freezecode())) / 4
      when :CRYSTALCAVERN                   then return (confucode() + poisoncode() + burncode() + sleepcode()) / 4
      when :MIRROR,:FLOWERGARDEN1,:FLOWERGARDEN2        then return oppstatdrop([0,0,0,0,0,0,1])
      when :FLOWERGARDEN3,:FLOWERGARDEN4            then return oppstatdrop([0,1,0,1,0,0,1])
      when :FLOWERGARDEN5                    then return oppstatdrop([0,2,0,2,0,0,2])
      when :NEWWORLD                       then return oppstatdrop([1,1,1,1,1,1,1])
      when :INVERSE, :PSYTERRAIN, :SKY            then return confucode()
      when :BEWITCHED                      then return (paracode() + poisoncode() + sleepcode()) / 3
      when :HAUNTED                      then return spoopycode()
      when :COLOSSEUM                      then return selfstatboost([1,0,0,0,0,0,0])
      else       return paracode()
    end
  end

  def nevermisscode(score)
    miniscore=1.0
    miniscore*=1.05 if score>=110
    return miniscore if @attacker.ability == :NOGUARD || @opponent.ability == :NOGUARD || (@attacker.ability==:FAIRYAURA && @battle.FE == :FAIRYTALE)
    miniscore*= (1 - 0.05*@attacker.stages[PBStats::ACCURACY]) if @attacker.stages[PBStats::ACCURACY]<0
    miniscore*= (1 + 0.05*@opponent.stages[PBStats::EVASION]) if @opponent.stages[PBStats::EVASION]>0
    miniscore*=1.2 if (@mondata.oppitemworks && @opponent.item == :LAXINCENSE) || (@mondata.oppitemworks && @opponent.item == :BRIGHTPOWDER)
    miniscore*=1.3 if accuracyWeatherAbilityActive?(@opponent)
    #miniscore*=3 if opponent.vanished && pbAIfaster?()
    return miniscore
  end

  def lockoncode
    return 0 if @opponent.effects[:LockOn]>0 || @opponent.effects[:Substitute]>0 || @attacker.ability == :NOGUARD && @opponent.ability == :NOGUARD || (@attacker.ability==:FAIRYAURA && @battle.FE == :FAIRYTALE)
    miniscore=1.0
    miniscore*=3 if @attacker.pbHasMove?(:INFERNO) || @attacker.pbHasMove?(:ZAPCANNON) || @attacker.pbHasMove?(:DYNAMICPUNCH)
    miniscore*=10 if @attacker.pbHasMove?(:GUILLOTINE) || @attacker.pbHasMove?(:SHEERCOLD) || @attacker.pbHasMove?(:GUILLOTINE) || @attacker.pbHasMove?(:FISSURE) || @attacker.pbHasMove?(:HORNDRILL)
    ministat = (@attacker.stages[PBStats::ACCURACY]<0) ? @attacker.stages[PBStats::ACCURACY] : 0
    miniscore*=1 + 0.1*ministat
    miniscore*=1 + 0.1*@opponent.stages[PBStats::EVASION]
    return miniscore
  end

  def forecode5me #after doing hundreds of these this is how i survive
    return 0 if @opponent.effects[:Foresight]
    ministat = (@opponent.stages[PBStats::EVASION]>0) ? @opponent.stages[PBStats::EVASION] : 0
    miniscore=1+0.10*ministat
    if @opponent.hasType?(:GHOST)
      miniscore*=1.5
      # Gen 9 Mod - Added Mind's Eye
      miniscore*=5 if !(@attacker.ability == :SCRAPPY || @attacker.ability == :MINDSEYE) && !@attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.basedamage > 0 && moveloop.pbType(@attacker) != :NORMAL && moveloop.pbType(@attacker) != :FIGHTING}
    end
    return miniscore
  end

  def miracode
    return 0 if @opponent.effects[:MiracleEye]
    ministat = (@opponent.stages[PBStats::EVASION]>0) ? @opponent.stages[PBStats::EVASION] : 0
    miniscore=1+0.10*ministat
    if @opponent.hasType?(:DARK)
      miniscore*=1.1
      miniscore*=2 if !@attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.basedamage > 0 && moveloop.pbType(@attacker) != :PSYCHIC}
    end
    return miniscore
  end

  def chipcode
    ministat = 0
    ministat+=@opponent.stages[PBStats::EVASION] if @opponent.stages[PBStats::EVASION]>0
    ministat+=@opponent.stages[PBStats::DEFENSE] if @opponent.stages[PBStats::DEFENSE]>0
    ministat+=@opponent.stages[PBStats::SPDEF]   if @opponent.stages[PBStats::SPDEF]>0
    miniscore=1 + 0.05*ministat
    return miniscore
  end

  def protectcode
    return 0 if unseenFistCheck(@opponent) # Gen 9 Mod - Method that also checks Punching Glove

    miniscore = 1.0
    miniscore *= 0.6
    miniscore *= 1.3 if @battle.trickroom > 0 && !pbAIfaster?()
    miniscore *= 1.3 if @battle.field.duration > 0 && getFieldDisruptScore(@attacker, @opponent) > 1.0
    miniscore *= 1.3 if @attacker.pbOpposingSide.screenActive?
    miniscore *= 1.2 if @attacker.pbOpposingSide.effects[:Tailwind] > 0
    miniscore *= 0.3 if checkAImoves(PBStuff::SETUPMOVE)
    if @attacker.ability == :SPEEDBOOST && !pbAIfaster?() && @battle.trickroom == 0
      miniscore *= 8
      # experimental -- cancels out drop if killing moves
      if @initial_scores.length > 0
        miniscore *= 6 if hasgreatmoves()
      end
      # end experimental
    end

    miniscore*=4 if @attacker.ability == :SLOWSTART && @attacker.turncount<5
    miniscore*=(1.2*hpGainPerTurn) if hpGainPerTurn > 1
    miniscore*=0.1 if (hpGainPerTurn-1) * @attacker.totalhp - @attacker.hp < 0 && (hpGainPerTurn(@opponent)-1) * @opponent.totalhp - @opponent.hp > 0
    if @opponent.status== :POISON || @opponent.status== :BURN || @opponent.effects[:SaltCure] # Gen 9 Mod - Added Salt Cure
      miniscore*=1.2
      miniscore*=1.3 if @opponent.effects[:Toxic]>0
      # Gen 9 Mod - Additional Checks for Salt Cure
      miniscore*=1.2 if @opponent.effects[:SaltCure] && @opponent.ability != :MAGICGUARD
      miniscore*=1.2 if @opponent.effects[:SaltCure] && @opponent.ability != :MAGICGUARD && (@opponent.hasType?(:WATER) || @opponent.hasType?(:STEEL))
    end
    if @attacker.status== :POISON || @attacker.status== :BURN || @attacker.effects[:SaltCure] # Gen 9 Mod - Added Salt Cure
      miniscore*=0.7
      miniscore*=0.3 if @attacker.effects[:Toxic]>1
      # Gen 9 Mod - Additional Checks for Salt Cure
      miniscore*=0.6 if @attacker.effects[:SaltCure] && @attacker.ability != :MAGICGUARD
      miniscore*=0.6 if @attacker.effects[:SaltCure] && @attacker.ability != :MAGICGUARD && (@attacker.hasType?(:WATER) || @attacker.hasType?(:STEEL))
    end
    miniscore*=1.3 if @opponent.effects[:LeechSeed]>=0
    miniscore*=4 if @opponent.effects[:PerishSong]!=0
    if (PBStuff::TRAPPINGABILITIESAI.include?(@attacker.ability) || (@attacker.ability == :MAGNETPULL && @opponent.hasType?(:STEEL))  || @opponent.effects[:MeanLook])
      miniscore*=4 if @opponent.effects[:PerishSong]==3
      miniscore*=8 if @opponent.effects[:PerishSong]==1
    end
    if @opponent.effects[:FutureSight] == 1
      miniscore *= 4
      if @battle.FE == :STARLIGHT || @battle.FE == :NEWWORLD
        miniscore *= 4
      end
    end
    miniscore*=0.3 if @opponent.status== :SLEEP || (@opponent.status== :FROZEN && !KAIZOMOD)
    if @opponent.vanished
      miniscore*=12
      miniscore*=1.5 if !pbAIfaster?()
    end
    miniscore*=0.2 if checkAImoves(PBStuff::PROTECTIGNORINGMOVE)
    if @attacker.effects[:Wish]>0
      miniscore*= checkAIdamage()>=@attacker.hp ? 15 : 2
    end
    miniscore/=(@attacker.effects[:ProtectRate]*2.0) if @attacker.effects[:ProtectRate] > 0
    miniscore*=0.7 if @attacker.effects[:ProtectRate] > 0 && @battle.doublebattle
    if @move.function == 0x133 || @move.function == 0x188 # obstruct now
      miniscore*=0.1 if checkAImoves([:WILLOWISP,:THUNDERWAVE,:TOXIC])
    end
    return miniscore
  end

  def protecteffectcode
    return 0 if seedProtection?(@attacker)
    miniscore = protectcode
    miniscore*=1.5 if @opponent.turncount==0
    miniscore*=1.3 if getAIMemory().any?{|moveloop| moveloop!=nil && moveloop.contactMove?}
    return miniscore
  end

  def feintcode
    return 1 if !checkAImoves(PBStuff::PROTECTMOVE)
    miniscore = 1.1
    miniscore*=1.2 if !PBStuff::RATESHARERS.include?(@opponent.lastMoveUsed)
    return miniscore
  end

  def mirrorcode(copycat=false)
    if copycat
      return 0 if !@battle.previousMove.is_a?(Symbol)
      mirrmove = PokeBattle_Move.pbFromPBMove(@battle,PBMove.new(@battle.previousMove.intern),@attacker)
    else
      return 0 if !@opponent.lastMoveUsed.is_a?(Symbol)
      mirrmove = PokeBattle_Move.pbFromPBMove(@battle,PBMove.new(@opponent.lastMoveUsed.intern),@attacker)
    end
    return 0 if mirrmove.canMirror?
    miniscore = [pbRoughDamage(mirrmove) / @opponent.hp.to_f, 100].min
    #score = pbGetMoveScore(mirrmove,@attacker,@opponent,@mondata.skill,rough)
    miniscore*=0.5 if !pbAIfaster?() && @attacker.ability != :PRANKSTER
    return miniscore
  end

  def yousecondcode
    return 0 if !pbAIfaster?(@move)

    miniscore = 1.0
    miniscore *= checkAImoves(PBStuff::SETUPMOVE) ? 0.8 : 1.5
    if checkAIpriority()
      miniscore *= 0.6
    else
      miniscore *= 1.5
    end
    miniscore *= (checkAIdamage() / (1.0 * @opponent.hp) > @initial_scores.max) ? 2 : 0.5 if @opponent.hp > 0 && @initial_scores.length > 0
    return miniscore
  end

  def coatcode
    miniscore=1.0
    if @attacker.lastMoveUsed==:MAGICCOAT
      miniscore*=0.5
    else
      miniscore*=1.5 if @attacker.hp==@attacker.totalhp
      miniscore*=3 if !@opponent.moves.any? {|moveloop| moveloop!=nil && moveloop.basedamage>0}
    end
    return miniscore
  end

  def snatchcode
    miniscore=1.0
    if @attacker.lastMoveUsed==:SNATCH
      miniscore*=0.5
    else
      miniscore*=1.5 if @opponent.hp==@opponent.totalhp
      miniscore*=2 if checkAImoves(PBStuff::SETUPMOVE)
      if @opponent.attack>@opponent.spatk
        miniscore*= (@attacker.attack>@attacker.spatk) ? 1.5 : 0.7
      else
        miniscore*= (@attacker.spatk>@attacker.attack) ? 1.5 : 0.7
      end
      if @battle.FE == :BACKALLEY
        subscore = selfstatboost([2,0,0,0,0,0,0]) +selfstatboost([0,2,0,0,0,0,0]) + selfstatboost([0,0,2,0,0,0,0]) +selfstatboost([0,0,0,2,0,0,0]) +selfstatboost([0,0,0,0,2,0,0])
        subscore/=5
        miniscore *= subscore
      end
    end
    return miniscore
  end

  def specialprotectcode
    return 0 if unseenFistCheck(@opponent) # Gen 9 Mod - Method that also checks Punching Glove
    miniscore = 1.0
    miniscore/=(@attacker.effects[:ProtectRate]*2.0) if @attacker.effects[:ProtectRate] > 0
    miniscore*=2 if @battle.doublebattle
    miniscore*=0.3 if checkAIdamage() || checkAImoves(PBStuff::SETUPMOVE)
    miniscore*=0.1 if checkAImoves(PBStuff::PROTECTIGNORINGMOVE)
    if @attacker.effects[:Wish]>0
      miniscore*=2 if checkAIdamage()>@attacker.hp || (@attacker.pbPartner.hp*(1.0/@attacker.pbPartner.totalhp))<0.25
    end
    return miniscore
  end

  def sleeptalkcode(initialscores=[])
    return 5 if @attacker.ability==:COMATOSE && @attacker.item == :CHOICEBAND
    if @attacker.ability!=:COMATOSE
      return 0 if @attacker.status!=:SLEEP || @attacker.statusCount<=1
    end
    return 5 if !@attacker.pbHasMove?(:SNORE)
    otherscores = 0
    for i in 0..3
      currentid = @attacker.moves[i].move || nil
      next if currentid.nil? || currentid == :SLEEPTALK
      snorescore = initialscores[i] if currentid == :SNORE
      otherscores += initialscores[i] if currentid != :SNORE
    end
    otherscores *= 0.5
    return 0.1 if otherscores<snorescore
    return 5
  end

  def metronomecode(scorethreshold)
    return 0 if @attacker.pbNonActivePokemonCount > 0
    return @initial_scores.any?{|scores| scores > scorethreshold} ? 0.5 : 1.5
  end

  def tormentcode # Gen 9 Mod - Added myceliumMightCheck
    return 0 if @opponent.effects[:Torment] || ((@opponent.ability == :AROMAVEIL || @opponent.pbPartner.ability == :AROMAVEIL) && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker)))
    if @opponent.lastMoveUsed.is_a?(Symbol)
      oldmove = PokeBattle_Move.pbFromPBMove(@battle,PBMove.new(@opponent.lastMoveUsed.intern),@opponent)
    else
      oldmove = -1
    end
    miniscore = 1.0
    miniscore*= pbAIfaster?(@move) ? 1.2 : 0.7
    if oldmove!=-1 && oldmove.basedamage > 0
      miniscore*=1.5
      bestmove, maxdam = checkAIMovePlusDamage()
      if oldmove!=-1 && bestmove.move == oldmove.move
        miniscore*=1.3
        miniscore*=1.5 if maxdam*3<@attacker.totalhp
      end
      miniscore*=1.5 if @attacker.moves.any? {|moveloop| moveloop!=nil && (PBStuff::PROTECTMOVE).include?(moveloop.move)} && !unseenFistCheck(@opponent) # Gen 9 Mod - Method that also checks Punching Glove
      miniscore*=1.3 if hpGainPerTurn>1
    else
      miniscore*=0.5
    end
    return miniscore
  end

  def imprisoncode
    return 0 if @opponent.effects[:Imprison]
    miniscore = 1.0
    subscore = 1
    ourmoves = Array.new(@attacker.moves.length)
    for i in 0..3
      ourmoves[i] = @attacker.moves[i].move
    end
    miniscore*=1.3 if ourmoves.include?(@opponent.lastMoveUsed)
    for j in getAIMemory()
      if ourmoves.include?(j.move)
        subscore+=1
        miniscore*=1.5 if j.isHealingMove?
      else
        miniscore*=0.7
      end
    end
    miniscore*=subscore
    return miniscore
  end

  def disablecode # Gen 9 Mod - Added myceliumMightCheck
    return 0 if @opponent.effects[:Disable]>0 || ((@opponent.ability == :AROMAVEIL || @opponent.pbPartner.ability == :AROMAVEIL) && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker)))
    if @opponent.lastMoveUsed.is_a?(Symbol)
      oldmove = PokeBattle_Move.pbFromPBMove(@battle,PBMove.new(@opponent.lastMoveUsed.intern),@opponent)
    else
      oldmove = -1
    end
    return 0 if oldmove == -1 && pbAIfaster?(@move,nil)
    miniscore=1.0
    miniscore*= (oldmove!=-1 && pbAIfaster?(@move,oldmove)) ? 1.2 : 0.7
    if oldmove!=-1 && (oldmove.basedamage>0 || oldmove.isHealingMove?)
      miniscore*=1.5
      bestmove, maxdam = checkAIMovePlusDamage()
      if bestmove.move == oldmove.move
        miniscore*=1.3
        miniscore*=1.5 if maxdam*3 < @attacker.totalhp && opponent.pbPartner.hp <= 0
        miniscore*=1.5 if maxdam*3 > @attacker.totalhp && opponent.pbPartner.hp > 0
      end
    else
      miniscore*=0.5
    end
    return miniscore
  end

  def tauntcode # Gen 9 Mod - Added myceliumMightCheck
    return @move.basedamage > 0 ? 1 : 0 if @opponent.effects[:Taunt]!=0 || ((@opponent.ability == :OBLIVIOUS || @opponent.ability == :AROMAVEIL || @opponent.pbPartner.ability == :AROMAVEIL) && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker)))
    if @opponent.lastMoveUsed.is_a?(Symbol)
      oldmove = PokeBattle_Move.pbFromPBMove(@battle,PBMove.new(@opponent.lastMoveUsed.intern),@opponent)
    else
      oldmove = -1
    end
    miniscore = 0.8
    miniscore*= (oldmove!=-1 && pbAIfaster?(@move,oldmove)) ? 1.5 : 0.7
    if pbGetMonRoles(@opponent).include?(:LEAD)
      miniscore*=1.2
    else
      miniscore*=0.8
    end
    miniscore*= @opponent.turncount<=1 ? 1.1 : 0.9
    miniscore*=1.3 if oldmove!=-1 && oldmove.isHealingMove?
    miniscore *= 0.6 if @battle.doublebattle
    return miniscore
  end

  def healblockcode
    return @move.basedamage > 0 ? 1 : 0 if @opponent.effects[:HealBlock] != 0
    miniscore = 1.0
    if @move.move == :PSYCHICNOISE # Gen 9 Score Nerf for Psychic Noise
      miniscore *= 1.5 if checkAIhealing()
    else
      miniscore *= 1.5 if pbAIfaster?(@move)
      miniscore *= 2.5 if checkAIhealing()
      miniscore *= ((hpGainPerTurn(@opponent)) * 4)
    end
    return miniscore
  end

  def encorecode # Gen 9 Mod - Added myceliumMightCheck
    return 0 if @opponent.effects[:Encore]>0 || ((@opponent.ability == :AROMAVEIL || @opponent.pbPartner.ability == :AROMAVEIL) && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker)))
    # Gen 9 Mod - Discourage status moves when current opponent has Good as Gold
    return 0 if @opponent.ability == :GOODASGOLD && @move.category == :status && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))
    return 0.2 if  !@opponent.lastMoveUsed.is_a?(Symbol)
    oldmove = PokeBattle_Move.pbFromPBMove(@battle,PBMove.new(@opponent.lastMoveUsed.intern),@opponent)
    miniscore = 1.0
    miniscore*=1.5 if [:BIGTOP,:CONCERT1,:CONCERT2,:CONCERT3,:CONCERT4].include?(@battle.FE)
    miniscore*= pbAIfaster?(@move,oldmove) || oldmove.basedamage==0 ? 2.0 : 0.2
    miniscore*=0.3 if pbRoughDamage(oldmove,@opponent,@attacker) > @attacker.hp
    if pbRoughDamage(oldmove,@opponent,@attacker) * 4 > @attacker.hp
      miniscore*=0.3
    elsif @opponent.stages[PBStats::SPEED]>0
      if (@opponent.hasType?(:DARK) || @attacker.ability != :PRANKSTER || @opponent.ability == :SPEEDBOOST)
        miniscore*=0.5
      else
        miniscore*=2
      end
    else
      miniscore*=2
    end
    return miniscore
  end

  def multihitcode
    miniscore = 1.0
    miniscore*=0.7 if @move.contactMove? && ((@mondata.oppitemworks && @opponent.item == :ROCKYHELMET) || @opponent.ability == :IRONBARBS || @opponent.ability == :ROUGHSKIN) && !(@mondata.attitemworks && (@attacker.item == :PROTECTIVEPADS || (@attacker.item == :PUNCHINGGLOVE && @move.punchMove?))) # Gen 9 Mod - Added Protective Pads and Punching Gloves/ attitemworks
    miniscore*=1.3 if notOHKO?(@opponent, @attacker, true)
    miniscore*=1.3 if @opponent.effects[:Substitute]>0
    miniscore*=1.3 if @attacker.itemWorks? && (@attacker.item == :RAZORFANG || @attacker.item == :KINGSROCK)
    miniscore*=0.5 if @attacker.ability == :TERASHELL
    return miniscore
  end

  def beatupcode(score) # only partner else multihit is used
    return 0 if @battle.pbPokemonCount(@battle.pbPartySingleOwner(@attacker.index))<1
    return 0 if @opponent.ability != :JUSTIFIED || @opponent.stages[PBStats::ATTACK]>3 || !@opponent.moves.any? {|moveloop| !moveloop.nil? && moveloop.pbIsPhysical?()} || pbRoughDamage > @opponent.hp
    return 0 if @opponent.ability != :STAMINA || @opponent.stages[PBStats::DEFENSE]>3
    return 999 if ragefisthelper()
    # return 0 if !ragefisthelper()
    score = 100-score
    if pbAIfaster?(nil, nil, @opponent, @attacker.pbOpposing1) && pbAIfaster?(nil, nil, @opponent, @attacker.pbOpposing2)
      score*=1.3
    else
      score*=0.7
    end
    return score
  end

  def ragefisthelper()
    return true if @opponent.moves.any? { |moveloop| !moveloop.nil? && moveloop.move == :RAGEFIST }
  end

  def hypercode()
    return 2 if !@battle.doublebattle && (!@battle.opponent.nil? && @battle.opponent.trainertype==:ZEL)
    miniscore = 1.0
    miniscore*=1.3 if @initial_scores[@score_index] >=110 && @battle.FE == :GLITCH
    if @initial_scores[@score_index] < 100

      miniscore*=0.5
      miniscore*=0.5 if checkAIhealing()
    end
    return miniscore if @battle.FE == :GLITCH # Glitch Field

    if @initial_scores.length>0
      miniscore*=0.3 if hasgreatmoves()
    end

    yourpartycount = @battle.pbPokemonCount(@battle.pbPartySingleOwner(@attacker.index))
    theirpartycount = @battle.pbPokemonCount(@battle.pbParty(@opponent.index))
    if theirpartycount > 1
      miniscore*=(10 -theirpartycount)*0.1
    else
      miniscore*=1.1
    end
    miniscore*=0.5 if @battle.doublebattle
    miniscore*=0.7 if theirpartycount>1 && yourpartycount==1

    return miniscore
  end

  def weaselslashcode
    miniscore = 1.0
    if @attacker.item == :POWERHERB
      miniscore=1.2 if !hasgreatmoves() && @move.move != :GEOMANCY
      miniscore=1.8 if @attacker.ability == :UNBURDEN
      return miniscore
    end
    if checkAIdamage()>@attacker.hp
      miniscore*=0.1
    elsif (checkAIdamage()*2)>@attacker.hp
      if !pbAIfaster?(@move)
        miniscore*=0.1
      else
        miniscore*=0.7
      end
    end
    miniscore*=0.6 if @attacker.hp/@attacker.totalhp.to_f<0.5
    if @opponent.effects[:TwoTurnAttack]!=0
      miniscore*= pbAIfaster?(@move) ? 2 : 0.5
    end
    miniscore*=0.1 if @initial_scores.any? {|score| score > 100}
    miniscore*=0.5 if @battle.doublebattle
    if @move.basedamage > 0
      miniscore*=0.1 if checkAImoves(PBStuff::PROTECTMOVE) && !(@move.contactMove? && unseenFistCheck(@attacker)) # Gen 9 Mod - Method that also checks Punching Glove
      miniscore*=0.7 if @initial_scores[@score_index] < 100
    elsif # probably geomancy
      miniscore*=0.4
    end
    return miniscore
  end

  def twoturncode
    miniscore=1.0
    if @attacker.item == :POWERHERB
      miniscore=1.2
      miniscore=1.8 if @attacker.ability == :UNBURDEN
      return miniscore
    end
    if @opponent.status== :POISON || @opponent.status== :BURN || @opponent.effects[:LeechSeed]>=0 || @opponent.effects[:MultiTurn]>0 || @opponent.effects[:Curse]
      miniscore*=1.2
    else
      miniscore*=0.8 if @battle.pbPokemonCount(@battle.pbPartySingleOwner(@opponent.index))>1
    end
    miniscore*=0.5 if !@attacker.status.nil? || @attacker.effects[:Curse] || @attacker.effects[:Attract]>-1 || @attacker.effects[:Confusion]>0
    miniscore*=hpGainPerTurn()
    miniscore*=0.7 if @attacker.pbOwnSide.screenActive? || @attacker.pbOwnSide.effects[:Tailwind]>0
    miniscore*=1.3 if @opponent.effects[:PerishSong]!=0 && @attacker.effects[:PerishSong]==0
    if pbAIfaster?()
      miniscore*=3 if @opponent.vanished
      miniscore*=1.1
    else
      miniscore*=0.8
      miniscore*=0.5 if checkAIhealing()
      miniscore*=0.7 if checkAIaccuracy()
    end
    miniscore*=0.1 if checkAImoves(PBStuff::PROTECTMOVE)
    return miniscore
  end

  def cooldownmovecode # Blood Moon, Gigaton Hammer
    miniscore = 1.0
    miniscore *= 0.7 if @opponent.effects[:Substitute] > 0
    miniscore *= 0.8 if checkAImoves(PBStuff::PROTECTMOVE) && !unseenFistCheck(@opponent) && @opponent.effects[:ProtectRate] < 1 # Gen 9 Mod - Method that also checks Punching Glove
    miniscore *= 0.9 if checkAImoves([:SUBSTITUTE]) && (!pbAIfaster?(@move) || @opponent.ability == :PRANKSTER)
    miniscore *= 0.8 if checkAImoves(PBStuff::TWOTURNMOVE) && !pbAIfaster?(@move)
    return miniscore
  end

  def firespincode()
    return @move.basedamage > 0 ? 1 : 0 if @initial_scores[@score_index] >= 110 || @opponent.effects[:MultiTurn]!=0 || @opponent.effects[:Substitute]>0
    miniscore=1.0
    miniscore*=1.2
    if @initial_scores.length>0
      miniscore*=1.2 if hasbadmoves(30)
    end
    if @opponent.totalhp == @opponent.hp
      miniscore*=1.2
    elsif @opponent.hp*2 < @opponent.totalhp
      miniscore*=0.8
    end
    miniscore*=1-0.05*statchangecounter(@opponent,1,7,1)
    if checkAIdamage()>@attacker.hp
      miniscore*=0.7
    elsif @attacker.hp*3<@attacker.totalhp
      miniscore*=0.7
    end
    miniscore*=1.5 if @opponent.effects[:LeechSeed]>=0
    miniscore*=1.3 if @opponent.effects[:Attract]>-1
    miniscore*=1.3 if @opponent.effects[:Confusion]>0
    miniscore*=1.2 if @mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL)
    miniscore*=1.1 if @attacker.moves.any? {|moveloop| moveloop!=nil && (PBStuff::PROTECTMOVE).include?(moveloop.move)} && !unseenFistCheck(@opponent) # Gen 9 Mod - Method that also checks Punching Glove
    miniscore*=1.3 if (@mondata.attitemworks && @attacker.item == :BINDINGBAND)
    miniscore*=1.1 if (@mondata.attitemworks && @attacker.item == :GRIPCLAW)
    return miniscore
  end

  def uproarcode
    miniscore = 1.0
    miniscore*=0.7 if @opponent.status== :SLEEP
    miniscore*=1.8 if checkAImoves([:REST])
    miniscore*=1.1 if @opponent.pbNonActivePokemonCount==0 || PBStuff::TRAPPINGABILITIESAI.include?(@attacker.ability) || (@attacker.ability == :MAGNETPULL && @opponent.hasType?(:STEEL))  || @opponent.effects[:MeanLook]>0
    miniscore*=0.7 if @move.pbTypeModifier(@move.pbType(@attacker),@attacker,@opponent)<4
    miniscore*=0.75 if @attacker.hp/@attacker.totalhp<0.75
    miniscore*=1+0.05*@attacker.stages[PBStats::SPATK] if @attacker.stages[PBStats::SPATK]<0
    return miniscore
  end

  def recovercode(amount=@attacker.totalhp/2.0)
    return 0 if @attacker.effects[:HealBlock]!=0
    return 0 if @attacker.effects[:Wish]>0
    miniscore = 1.0
    amount *= 0.67 if @mondata.skill>=BESTSKILL && @battle.FE == :BACKALLEY
    recoverhp = [@attacker.hp + amount,@attacker.totalhp].min # the amount of hp we expect to have after recover
    if @mondata.skill>=BESTSKILL
      bestmove, maxdam = checkAIMovePlusDamage()
      miniscore *= 0.2 if maxdam > amount # we take more damage than we heal
      miniscore *= 0.6 if maxdam > 1.4 * amount && [0x1C, 0x20].include?(bestmove.function)
      if maxdam>@attacker.hp
        if maxdam > recoverhp #if we expect to die after healing, don't bother
          return 0
        else # if we're not going to die, we really want to recover
          miniscore*=5
          if @initial_scores.length>0 && amount > maxdam
            miniscore*=6 if hasgreatmoves() # offset killing moves
          end
        end
      else # if we're not going to die
        miniscore*=2 if maxdam*1.5>@attacker.hp # if a second attack would kill us next turn,
        if !pbAIfaster?(@move) # and we're slower,  then heal pre-emptively
          if maxdam*2>@attacker.hp
            miniscore*=5
            if @initial_scores.length>0 && amount > maxdam
              miniscore*=6 if hasgreatmoves() # offset killing moves
            end
          end
        end
      end
    elsif @mondata.skill>=MEDIUMSKILL
      miniscore*=3 if checkAIdamage()>@attacker.hp
    end
    yourpartycount = @battle.pbPokemonCount(@battle.pbPartySingleOwner(@attacker.index))
    theirpartycount = @battle.pbPokemonCount(@battle.pbParty(@opponent.index))
    miniscore*=1.1 if yourpartycount == 1
    miniscore*=0.3 if theirpartycount == 1 && hasgreatmoves()
    miniscore*=0.7 if @opponent.moves.any? {|moveloop| moveloop!=nil && (PBStuff::SETUPMOVE).include?(moveloop.move)}
    if (@attacker.hp.to_f)/@attacker.totalhp<0.5
      miniscore*=1.5
      miniscore*=2 if @attacker.effects[:Curse]
      if @attacker.hp*4<@attacker.totalhp
        miniscore*=1.5 if @attacker.status== :POISON
        miniscore*=2 if @attacker.effects[:LeechSeed]>=0
        if @attacker.hp<@attacker.totalhp*0.13
          miniscore*=2 if @attacker.status== :BURN
          # Gen 9 Mod - Hail/Snow/Both consider HAIL only when it is damaging
          miniscore*=2 if (@battle.pbWeather== :HAIL && !@attacker.hasType?(:ICE) && (HAILSNOWMOD != "Snow" || KAIZOMOD)) || (@battle.pbWeather== :SANDSTORM && !@attacker.hasType?(:ROCK) && !@attacker.hasType?(:GROUND) && !@attacker.hasType?(:STEEL)) || (@battle.pbWeather== :SHADOWSKY && !@attacker.hasType?(:SHADOW))
        end
      end
    else
      miniscore*=0.9
    end
    if @attacker.effects[:Toxic]>0
      miniscore*=0.5
      miniscore*=0.5 if @attacker.effects[:Toxic]>3
    end
    # Gen 9 Mod - Recovering is discentivized if Salt Cured
    if @attacker.effects[:SaltCure]
      miniscore*=0.8 if @attacker.ability != :MAGICGUARD
      miniscore*=0.8 if @attacker.ability != :MAGICGUARD && (@attacker.hasType?(:WATER) || @attacker.hasType?(:STEEL))
    end
    miniscore*=1.1 if @attacker.status== :PARALYSIS || @attacker.effects[:Attract]>=0 || @attacker.effects[:Confusion]>0
    if @opponent.status== :POISON || @opponent.status== :BURN || @opponent.effects[:LeechSeed]>=0 || @opponent.effects[:Curse]
      miniscore*=1.3
      miniscore*=1.3 if @opponent.effects[:Toxic]>0
    end
    if @opponent.effects[:SaltCure]
      miniscore*=1.2 if @opponent.effects[:SaltCure] && @opponent.ability != :MAGICGUARD
      miniscore*=1.2 if @opponent.effects[:SaltCure] && @opponent.ability != :MAGICGUARD && (@opponent.hasType?(:WATER) || @opponent.hasType?(:STEEL))
    end
    miniscore*=1.3 if checkAImoves(PBStuff::CONTRARYBAITMOVE)
    miniscore*=1.2 if @opponent.vanished || @opponent.effects[:HyperBeam]>0
    return miniscore if move.function == 0xD7 #Wish doesn't do any of the remaining checks
    if ((@attacker.hp.to_f)/@attacker.totalhp)>0.8
      miniscore=0
    elsif ((@attacker.hp.to_f)/@attacker.totalhp)>0.6
      miniscore*=0.6
    elsif ((@attacker.hp.to_f)/@attacker.totalhp)<0.25
      miniscore*=2
    end
    return miniscore
  end

  def wishcode
    miniscore = recovercode
    maxdam = checkAIdamage()
    recoverhp = [@attacker.hp + @attacker.totalhp/2.0,@attacker.totalhp].min # the amount of hp we expect to have after recover
    if @attacker.moves.any? {|moveloop| moveloop!=nil && (PBStuff::PROTECTMOVE).include?(moveloop.move)} && !unseenFistCheck(@opponent) # Gen 9 Mod - Method that also checks Punching Glove # if we have protect
      if (maxdam > @attacker.hp) && (maxdam < recoverhp) && !hasgreatmoves() # and we expect to die, and can't kill the opponent, and we can save ourselves
        miniscore*=4
      else
        miniscore*=0.6
      end
    else # if we don't have protect, we want to be using wish earlier
      miniscore*=2 if (maxdam*2 > @attacker.hp) && maxdam < @attacker.hp && (maxdam * 2 < recoverhp)
    end
    if @mondata.roles.include?(:CLERIC)
      miniscore*=1.1 if @battle.pbPartySingleOwner(@attacker.index).any?{|i| i.hp.to_f<0.6*i.totalhp && i.hp.to_f>0.3*i.totalhp}
    end
    return miniscore
  end

  def restcode
    return 0 if !@attacker.pbCanSleep?(false,true,true)
    return 0 if @attacker.hp*(1.0/@attacker.totalhp)>=0.8
    miniscore=1.0
    maxdam = checkAIdamage()
    if maxdam>@attacker.hp && maxdam * 2 < @attacker.totalhp * hpGainPerTurn
      miniscore*=3
    elsif @mondata.skill >= BESTSKILL && maxdam*2 < @attacker.totalhp * hpGainPerTurn
      miniscore*=1.5 if maxdam*1.5>@attacker.hp
      miniscore*=2 if  maxdam*2>@attacker.hp && !pbAIfaster?()
    end
       miniscore*=@attacker.hp < 0.5 * @attacker.totalhp ? 1.5 : 0.5
    miniscore*=1.2 if (@mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL))
    if @opponent.status== :POISON || @opponent.status== :BURN || @opponent.effects[:LeechSeed]>=0 || @opponent.effects[:Curse] || @opponent.effects[:SaltCure]
      miniscore*=1.3
      miniscore*=1.3 if @opponent.effects[:Toxic]>0
      # Gen 9 Mod - Additional Checks for Salt Cure
      miniscore*=1.2 if @opponent.effects[:SaltCure] && @opponent.ability != :MAGICGUARD
      miniscore*=1.2 if @opponent.effects[:SaltCure] && @opponent.ability != :MAGICGUARD && (@opponent.hasType?(:WATER) || @opponent.hasType?(:STEEL))
    end
    if @attacker.status== :POISON
      miniscore*=1.3
      miniscore*=1.3 if @opponent.effects[:Toxic]>0
    end
    if @attacker.status== :BURN
      miniscore*=1.3
      miniscore*=1.5 if @attacker.spatk<@attacker.attack
    end
    miniscore*=1.3 if @attacker.status== :PARALYSIS
    miniscore*=1.3 if checkAImoves(PBStuff::CONTRARYBAITMOVE)
    if !(@attacker.item == :LUMBERRY || @attacker.item == :CHESTOBERRY || hydrationCheck(@attacker))
      miniscore*=0.8
      if maxdam*2 > @attacker.totalhp
          miniscore*=0.4
      elsif maxdam*3 < @attacker.totalhp
        miniscore*=1.3
        if @initial_scores.length>0
          miniscore*=6 if hasgreatmoves()
        end
      end
      miniscore*=0.7 if checkAImoves([:WAKEUPSLAP,:NIGHTMARE,:DREAMEATER]) || @opponent.ability == :BADDREAMS
      miniscore*=1.3 if @attacker.pbHasMove?(:SLEEPTALK)
      miniscore*=1.2 if @attacker.pbHasMove?(:SNORE)
      miniscore*=1.1 if @attacker.ability == :SHEDSKIN || @attacker.ability == :EARLYBIRD
      miniscore*=0.8 if @battle.doublebattle
    else
      if @attacker.item == :LUMBERRY || @attacker.item == :CHESTOBERRY
        miniscore*= @attacker.ability == :HARVEST ? 1.2 : 0.8
      end
    end
    if @attacker.crested == :BASTIODON
      if @attacker.hp*(1.0/@attacker.totalhp)>=0.8
        reflectdamage=maxdam
        reflectdamage=@attacker.hp-1 if maxdam>=@attacker.hp
        reflectdamage*=0.5
        if (reflectdamage>=@opponent.hp)
          miniscore*=4
          miniscore*=6 if @initial_scores.length>0 && hasgreatmoves() #experimental -- cancels out drop if killing moves
        end
      end
    end
    if !@attacker.status.nil?
      miniscore*=1.4
      miniscore*=1.2 if @attacker.effects[:Toxic]>0
    end
    return miniscore
  end

  def aquaringcode
    return 0 if ((@move.function == 0xda || @move.function == 0x187) && @attacker.effects[:AquaRing]) || (@move.function == 0xdb && @attacker.effects[:Ingrain])
    miniscore = 1.0
    attackerHPpercent = @attacker.hp/@attacker.totalhp
    miniscore*=1.2 if attackerHPpercent>0.75
    if attackerHPpercent<0.50
      miniscore*=0.7
      miniscore*=0.5 if attackerHPpercent<0.33
    end
    miniscore*=1.2 if checkAIhealing()
    miniscore*=1.2 if @attacker.moves.any? {|moveloop| moveloop!=nil && (PBStuff::PROTECTMOVE).include?(moveloop.move)} && !unseenFistCheck(@opponent) # Gen 9 Mod - Method that also checks Punching Glove
    miniscore*=0.8 if @attacker.moves.any? {|moveloop| moveloop!=nil && (PBStuff::PIVOTMOVE).include?(moveloop.move)}
    if checkAIdamage()*5 < @attacker.totalhp && (getAIMemory().length > 0)
      miniscore*=1.2
    elsif checkAIdamage() > @attacker.totalhp*0.4
      miniscore*=0.3
    end
    miniscore*=1.2 if (@mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL) || @mondata.roles.include?(:TANK))
    miniscore*=0.3 if checkAImoves(PBStuff::PHASEMOVE)
    miniscore*=0.5 if @battle.doublebattle
    return miniscore
  end

  def absorbcode(score)
    return @move.basedamage > 0 ? 1 : 0 if (@attacker.hp==@attacker.totalhp && pbAIfaster?(@move) || @opponent.effects[:Substitute]>0)
    hpdrained = ([score,100].min)*@opponent.hp*0.01/2.0
    hpdrained*= 1.5 if @move.function == 0x139 #Draining Kiss
    hpdrained*= 1.5 if Rejuv && @battle.FE == :ELECTERRAIN && @move.move == :PARABOLICCHARGE
    if Rejuv && @battle.FE == :GRASSY
      hpdrained*= 1.6 if @attacker.itemWorks? && @attacker.item == :BIGROOT
    else
      hpdrained*= 1.3 if @attacker.itemWorks? && @attacker.item == :BIGROOT
    end
    hpdrained *= 1.3 if @attacker.crested == :SHIINOTIC
    if pbAIfaster?(@move)
      hpdrained = (@attacker.totalhp-@attacker.hp) if hpdrained > (@attacker.totalhp-@attacker.hp)
    else
      maxdam = checkAIdamage()
      hpdrained = (@attacker.totalhp-(@attacker.hp-maxdam)) if hpdrained > (@attacker.totalhp-(@attacker.hp-maxdam))
    end
    miniscore = hpdrained/@opponent.totalhp.to_f
    return (1-miniscore) if @opponent.ability == :LIQUIDOOZE
    miniscore*=0.5 #arbitrary multiplier to make it value the HP less
    miniscore+=1
    return miniscore
  end

  def healpulsecode
    return 0 if @opponent.index != @attacker.pbPartner.index || @attacker.effects[:HealBlock]!=0 || @opponent.effects[:HealBlock]!=0
    miniscore=1.0
    if @opponent.hp > 0.8*@opponent.totalhp
      if !pbAIfaster?(nil, nil, @attacker, @attacker.pbOpposing1) && !pbAIfaster?(nil, nil, @attacker, @attacker.pbOpposing2)
        miniscore*=0.5
      else
        return 0
      end
    elsif @opponent.hp < 0.7*@opponent.totalhp && @opponent.hp > 0.3*@opponent.totalhp
      miniscore*=3
    elsif @opponent.hp < 0.3*@opponent.totalhp
      miniscore*=1.7
    end
    if @opponent.status== :POISON || @opponent.status== :BURN || @opponent.effects[:LeechSeed]>=0 || @opponent.effects[:Curse] || @opponent.effects[:SaltCure]
      miniscore*=0.8
      miniscore*=0.7 if @opponent.effects[:Toxic]>0
      miniscore*=0.9 if @opponent.effects[:SaltCure] && @opponent.ability != :MAGICGUARD
      miniscore*=0.9 if @opponent.effects[:SaltCure] && @opponent.ability != :MAGICGUARD && (@opponent.hasType?(:WATER) || @opponent.hasType?(:STEEL))
    end
    return miniscore
  end

  def lifedewcode(amount=@attacker.totalhp/4.0)
    miniscore = recovercode(amount)
    miniscore += healpulsecode*0.5
    if @move == :JUNGLEHEALING
      miniscore += partyrefreshcode()
    end
    return miniscore
  end

  def deathcode
    miniscore = 1.0
    miniscore*=0.7
    miniscore*=0.3 if ((@opponent.effects[:Disguise] || (@opponent.effects[:IceFace] && (@move.pbIsPhysical? || @battle.FE == :FROZENDIMENSION))) && !moldBreakerCheck(@attacker)) || @opponent.effects[:Substitute]>0
    miniscore*=0.3 if checkAImoves(PBStuff::PROTECTMOVE) && !(@move.contactMove? && unseenFistCheck(@attacker)) # Gen 9 Mod - Method that also checks Punching Glove
    return miniscore if @move.function == 0xe1 #Final gambit can go home
    if @attacker.hp==@attacker.totalhp
      miniscore*=0.2
    else
      miniscore*=1-(@attacker.hp.to_f/@attacker.totalhp)
      if @attacker.hp*4<@attacker.totalhp
        miniscore*=1.3
        miniscore*=1.4 if (@mondata.attitemworks && @attacker.item == :CUSTAPBERRY)
      end
    end
    miniscore*=1.2 if @mondata.roles.include?(:LEAD)
    return miniscore
  end

  def gambitcode
    miniscore = 0.7
    miniscore*= pbAIfaster?() ? 1.1 : 0.5
    miniscore*= @attacker.hp > @opponent.hp ? 1.1 : 0.5
    miniscore*=0.2 if notOHKO?(@opponent, @attacker, true)
    return miniscore
  end

  def mementcode(score)
    miniscore=1.0
    score = 15 if @initial_scores.length>0 && hasbadmoves(10)
    if @attacker.hp==@attacker.totalhp
      miniscore*=0.2
    else
      miniscore = 1-@attacker.hp*(1.0/@attacker.totalhp)
      miniscore*=1.3 if @attacker.hp*4<@attacker.totalhp
    end
    miniscore*=oppstatdrop([0,0,0,2,2,0,0])
    return miniscore*score
  end

  def grudgecode
    miniscore = 1.0
    damcount = getAIMemory().count {|moveloop| moveloop!=nil && moveloop.basedamage > 0}
    miniscore*=3 if getAIMemory().length >= 4 && damcount==1
    if @attacker.hp==@attacker.totalhp
      miniscore*=0.2
    else
      miniscore*=1-(@attacker.hp/@attacker.totalhp)
      if @attacker.hp*4<@attacker.totalhp
        miniscore*=1.3
        miniscore*=1.4 if (@mondata.attitemworks && @attacker.item == :CUSTAPBERRY)
      end
    end
    miniscore*= pbAIfaster?(@move) ? 1.3 :0.5
    return miniscore
  end

  def healwishcode
    miniscore = 1.0
    count = 0
    for mon in @battle.pbPartySingleOwner(@attacker.index)
      next if mon.nil?

      count += 1 if mon.hp != mon.totalhp
    end
    count -= 1 if @attacker.hp != @attacker.totalhp
    return 0 if count == 0

    maxscore = 0
    for mon in @battle.pbPartySingleOwner(@attacker.index)
      next if mon.nil?

      if mon.hp != mon.totalhp
        miniscore = 1 - mon.hp * (1.0 / mon.totalhp)
        miniscore *= 2 if !mon.status.nil?
        maxscore = miniscore if miniscore > maxscore
      end
    end
    miniscore *= maxscore
    if @attacker.hp == @attacker.totalhp
      miniscore *= 0.2
    else
      miniscore *= 1 - (@attacker.hp / @attacker.totalhp)
      if @attacker.hp * 4 < @attacker.totalhp
        miniscore *= 1.3
        miniscore *= 1.4 if @mondata.attitemworks && @attacker.item == :CUSTAPBERRY
      end
    end
    miniscore *= pbAIfaster?(@move) ? 1.1 : 0.5
    return miniscore
  end

  def revivalcode
    miniscore = 1.0
    count = 0
    for mon in @battle.pbPartySingleOwner(@attacker.index)
      next if mon.nil?

      count += 1 if mon.hp == 0
    end
    return 0 if count == 0

    for mon in @battle.pbPartySingleOwner(@attacker.index)
      next if mon.nil?

      if mon.hp <= 0
        miniscore +=  0.1 if mon.speed > @opponent.pbSpeed
      end
    end
    if @attacker.hp == @attacker.totalhp
      miniscore *= 0.9
    else
      miniscore *= 1.5 - (@attacker.hp / @attacker.totalhp)
      if @attacker.hp * 4 < @attacker.totalhp
        miniscore *= 1.5
        miniscore *= (@mondata.attitemworks && @attacker.item == :CUSTAPBERRY && !checkAIpriority()) ? 2 : 1.5
      end
    end
    miniscore *= pbAIfaster?(@move) ? 1.5 : 0.8
    return miniscore
  end

  def endurecode
    return 0 if @attacker.hp==1
    return 0 if notOHKO?(@attacker, @opponent, true)
    # Gen 9 Mod - Hail/Snow/Both consider HAIL only when it is damaging
    return 0 if (@battle.pbWeather== :HAIL && !@attacker.hasType?(:ICE) && (HAILSNOWMOD != "Snow" || KAIZOMOD)) || (@battle.pbWeather== :SANDSTORM && !(@attacker.hasType?(:ROCK) || @attacker.hasType?(:GROUND) || @attacker.hasType?(:STEEL))) || (@battle.pbWeather== :SHADOWSKY && !@attacker.hasType?(:SHADOW))
    return 0 if @attacker.status== :POISON || @attacker.status== :BURN || @attacker.effects[:LeechSeed]>=0 || @attacker.effects[:Curse]
    return 0 if checkAIdamage()<@attacker.hp
    miniscore=1.0
    miniscore*= (pbAIfaster?(nil, nil, @attacker, @opponent.pbPartner)) ? 1.3 : 0.5
    if pbAIfaster?(nil, nil, @attacker, @opponent.pbPartner)
      miniscore*=3 if (@attacker.pbHasMove?(:PAINSPLIT) || @attacker.pbHasMove?(:FLAIL) || @attacker.pbHasMove?(:REVERSAL))
      miniscore*=5 if @attacker.pbHasMove?(:ENDEAVOR)
      miniscore*=5 if @opponent.effects[:TwoTurnAttack]!=0
    end
    miniscore*=1.5 if @opponent.status== :POISON || @opponent.status== :BURN || @opponent.effects[:LeechSeed]>=0 || @opponent.effects[:Curse]
    miniscore/=(@attacker.effects[:ProtectRate]*2.0) if @attacker.effects[:ProtectRate] > 0
    return miniscore
  end

  def destinycode
    return 0 if @attacker.effects[:DestinyRate] && @battle.FE != :HAUNTED
    miniscore=1.0
    miniscore*=3 if getAIMemory().length>=4 && getAIMemory().all?{|moveloop| moveloop!=nil && moveloop.basedamage>0}
    miniscore*=0.1 if @initial_scores.length>0 && hasgreatmoves()
    miniscore*= (pbAIfaster?(@move)) ? 1.5 : 0.5
    if @attacker.hp==@attacker.totalhp
      miniscore*=0.2
    else
      miniscore*=1-@attacker.hp*(1.0/@attacker.totalhp)
      if @attacker.hp*4<@attacker.totalhp
        miniscore*=1.3
        miniscore*=1.5 if (@mondata.attitemworks && @attacker.item == :CUSTAPBERRY)
      end
    end
    return miniscore
  end

  def phasecode
    # Gen 9 Mod - Added Guard Dog
    return @move.basedamage > 0 ? 1 : 0 if @opponent.effects[:Ingrain] || @opponent.ability == :SUCTIONCUPS || @opponent.ability == :GUARDDOG || @opponent.pbNonActivePokemonCount==0 || @battle.FE == :COLOSSEUM
    return @move.basedamage > 0 ? 1 : 0 if @opponent.effects[:PerishSong]>0 || @opponent.effects[:Yawn]>0
    miniscore=1.0
    miniscore*=0.8 if pbAIfaster?()
    miniscore*= (1+ 0.1*statchangecounter(@opponent,1,7))
    miniscore*=1.3 if @opponent.status== :SLEEP
    miniscore*=1.3 if @opponent.ability == :SLOWSTART
    miniscore*=1.5 if @opponent.item.nil? && @opponent.unburdened
    miniscore*=0.7 if @opponent.ability == :INTIMIDATE
    # Gen 9 Mod - Discourage phasing when opponent's ability is Supersweet Syrup.
    miniscore*=0.7 if @opponent.ability == :SUPERSWEETSYRUP
    # Gen 9 Mod - Discourage status moves when current opponent has Good as Gold.
    miniscore*=0 if @opponent.ability == :GOODASGOLD && @move.category == :status && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))
    miniscore*=0.7 if @opponent.ability == :PRESSURE || @opponent.ability == :UNNERVE
    miniscore*=0.7 if @battle.FE == :CITY && @opponent.ability == :FRISK
    miniscore*=0.7 if @opponent.crested == :THIEVUL
    # Gen 9 Mod - Added Hospitality
    miniscore*=0.5 if @opponent.ability == :REGENERATOR || @opponent.ability == :NATURALCURE || @opponent.ability == :HOSPITALITY
    miniscore*=1.1 if @opponent.pbOwnSide.effects[:ToxicSpikes]>0
    miniscore*=1.4 if @opponent.effects[:Substitute]>0
    miniscore*=(@opponent.pbOwnSide.effects[:StealthRock]) ? 1.3 : 0.8
    miniscore*=(@opponent.pbOwnSide.effects[:Spikes]>0) ? (1.2**@opponent.pbOwnSide.effects[:Spikes]) : 0.8
    return miniscore
  end

  def pivotcode
    return 0 if @attacker.pbNonActivePokemonCount==1 && $game_switches[:Last_Ace_Switch]
    return @move.basedamage > 0 ? 1 : 0 if @attacker.pbNonActivePokemonCount==0 || @battle.FE == :COLOSSEUM
    miniscore=1.0
    miniscore*=0.7 if @attacker.pbOwnSide.effects[:StealthRock]
    miniscore*=0.6 if @attacker.pbOwnSide.effects[:StickyWeb]
    miniscore*=0.9**@attacker.pbOwnSide.effects[:Spikes] if @attacker.pbOwnSide.effects[:Spikes]>0
    miniscore*=0.9**@attacker.pbOwnSide.effects[:ToxicSpikes] if @attacker.pbOwnSide.effects[:ToxicSpikes]>0
    miniscore*=1.1 if @opponent.ability == :INTIMIDATE
    # Gen 9 Mod - Encourage pivoting when ability is Supersweet Syrup.
    miniscore*=1.1 if @attacker.ability == :SUPERSWEETSYRUP
    # Gen 9 Mod - Great boost to miniscore if Zero To Hero and not Hero Form.
    miniscore*=2 if @attacker.ability == :ZEROTOHERO && attacker.form == 0
    if @opponent.ability == :PRESSURE || @opponent.ability == :UNNERVE
      if @battle.FE == :DIMENSIONAL || @battle.FE == :FROZENDIMENSIONAL
        miniscore *= 1.2
      else
        miniscore *= 1.1
      end
    end
    miniscore*=1.1 if @battle.FE == :CITY && @opponent.ability == :FRISK
    miniscore*=1.1 if @opponent.crested == :THIEVUL
    # Gen 9 Mod - Added Hospitality
    if (@attacker.ability == :REGENERATOR ||@attacker.ability == :HOSPITALITY) && ((@attacker.hp.to_f)/@attacker.totalhp)<0.75
      miniscore*=1.2
      miniscore*=1.2 if @attacker.ability == :REGENERATOR && ((@attacker.hp.to_f)/@attacker.totalhp)<0.5
      miniscore*=1.2 if @attacker.ability == :HOSPITALITY && ((@attacker.pbPartner.hp.to_f)/@attacker.pbPartner.totalhp)<0.5
    end
    miniscore*=1.5 if @mondata.partyroles.any? {|role| role.include?(:SWEEPER)} && @move.move == :PARTINGSHOT
    miniscore*=1.2 if @mondata.partyroles.any? {|role| role.include?(:SWEEPER)} && (@move.move == :UTURN || @move.move == :VOLTSWITCH || @move.move == :FLIPTURN) && !pbAIfaster?() # Gen 9 Mod - Added Flip Turn
    miniscore*0.25 if @attacker.isGiga?

    movebackup = @move
    attackerbackup = @attacker
    oppbackup = @opponent
    miniscore*=0.2 if getSwitchInScoresParty(pbAIfaster?(@move)).max < 50
    @move = movebackup ; @attacker = attackerbackup ; @opponent = oppbackup

    if @move.move == :BATONPASS #Baton Pass
      miniscore*=1+0.3*statchangecounter(@attacker,1,7)
      miniscore*=0 if @attacker.effects[:PerishSong]>0
      miniscore*=1.4 if @attacker.effects[:Substitute]>0
      miniscore*=0.5 if @attacker.effects[:Confusion]>0
      miniscore*=0.5 if @attacker.effects[:LeechSeed]>=0
      miniscore*=0.5 if @attacker.effects[:Curse]
      miniscore*=0.5 if @attacker.effects[:Yawn]>0
      miniscore*=0.5 if @attacker.turncount<1
      miniscore*=1.3 if !@attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.basedamage>0}
      miniscore*=1.2 if @attacker.effects[:Ingrain] || @attacker.effects[:AquaRing]
      if pbAIfaster?(@move)
        miniscore*=1.8 if checkAIdamage() > @attacker.hp && (getAIMemory().length > 0)
      else
        miniscore*=2 if (checkAIdamage()*2) > @attacker.hp && (getAIMemory().length > 0)
      end
    else    #U-turn / Volt Switch / Parting Shot / Gen 9 Mod - Added Flip Turn
      miniscore*= 1-0.15*statchangecounter(@attacker,1,7,-1)
      miniscore*=1-0.25*statchangecounter(@attacker,1,7,1)
      miniscore*=1.1 if @mondata.roles.include?(:LEAD)
      miniscore*=1.1 if @mondata.roles.include?(:PIVOT)
      miniscore*=1.2 if pbAIfaster?(@move)
      miniscore*=1.3 if @attacker.effects[:Toxic]>0 || @attacker.effects[:Attract]>-1 || @attacker.effects[:Confusion]>0 || @attacker.effects[:Yawn]>0
      # Gen 9 Mod - Switching out is heavily favored if Salt Cured - Only way to get rid of it.
      miniscore*=1.2 if @attacker.effects[:SaltCure] && @opponent.ability != :MAGICGUARD
      miniscore*=1.3 if @attacker.effects[:SaltCure] && @attacker.ability != :MAGICGUARD && (@attacker.hasType?(:WATER) || @attacker.hasType?(:STEEL))
      miniscore*=1.5 if @attacker.effects[:LeechSeed]>-1
      miniscore*=0.5 if @attacker.effects[:Substitute]>0
      miniscore*=1.5 if @attacker.effects[:PerishSong]>0 || @attacker.effects[:Curse]
      if pbAIfaster?(@move)
        @opponent.hp -= pbRoughDamage()
        can_hard_switch = false
        @battle.pbParty(@attacker.index).each_with_index  {|mon, monindex|
          next if mon.nil? || mon.hp <= 0 || mon.isEgg?
          next if !@battle.pbIsOwner?(@attacker.index,monindex)

          can_hard_switch = true if shouldHardSwitch?(@attacker, monindex)
        }
        miniscore *= 0.2 if !can_hard_switch && @opponent.hp > 0
      end
    end
    miniscore*=0.5 if hasgreatmoves()
    if hasbadmoves(25)
      miniscore*=2
    elsif hasbadmoves(40)
      miniscore*=1.2
    end
    return miniscore
  end

  def meanlookcode
    miniscore=1.0
    if @opponent.effects[:MeanLook]>=0 || @opponent.effects[:Ingrain] ||
      (@opponent.hasType?(:GHOST) && @move.move == :THOUSANDWAVES) ||
      secondaryEffectNegated?() || @opponent.effects[:Substitute]>0 || @battle.pbPokemonCount(@battle.pbPartySingleOwner(@opponent.index))==1
      return (@move.basedamage > 0) ? miniscore : 0
    end
    miniscore*=0.1 if checkAImoves(PBStuff::PIVOTMOVE)
    miniscore*=0.1 if @opponent.ability == :RUNAWAY
    # Gen 9 Mod - Discourage status moves when current opponent has Good as Gold
    miniscore*=0 if @opponent.ability == :GOODASGOLD && @move.category == :status && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))
    miniscore*=1.5 if @attacker.pbHasMove?(:PERISHSONG)
    miniscore*=4   if @opponent.effects[:PerishSong]>0
    miniscore*=0   if PBStuff::TRAPPINGABILITIESAI.include?(@attacker.ability) || (@attacker.ability == :MAGNETPULL && @opponent.hasType?(:STEEL))
    miniscore*=1.3 if @opponent.effects[:Attract]>=0
    miniscore*=1.3 if @opponent.effects[:LeechSeed]>=0
    miniscore*=1.5 if @opponent.effects[:Curse]
    miniscore*=1.1 if @opponent.effects[:Confusion]>0
    miniscore*=0.7 if @attacker.moves.any? {|moveloop| moveloop!=nil && (PBStuff::PHASEMOVE).include?(moveloop.move)}
    miniscore*=1-0.05*statchangecounter(@opponent,1,7)
    miniscore=1.0 if miniscore < 1.0 && @move.basedamage > 0
    return miniscore
  end

  def knockcode # Gen 9 Mod - Added myceliumMightCheck
    return @move.basedamage > 0 ? 1 : 0 if @opponent.effects[:Substitute]>0
    return @move.basedamage > 0 ? 1 : 0 unless (@opponent.ability != :STICKYHOLD || (moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))) && @opponent.item && !@battle.pbIsUnlosableItem(@opponent,@opponent.item)
    if @opponent.item == :LEFTOVERS || (@opponent.item == :BLACKSLUDGE) && @opponent.hasType?(:POISON)
      return 1.3
    elsif @opponent.item == :LIFEORB || @opponent.item == :CHOICESCARF || @opponent.item == :CHOICEBAND || @opponent.item == :CHOICESPECS || @opponent.item == :ASSAULTVEST
      return 1.2
    # Gen 9 Mod - Added Cud Chew --> Add Ripen and Cud Chew to the knock off code
    elsif pbIsBerry?(@opponent.item) && (@opponent.ability == :HARVEST || @opponent.ability == :RIPEN || @opponent.ability == :CUDCHEW)
      return 1.3
    end
    return 1
  end

  def covetcode # Gen 9 Mod - Added myceliumMightCheck
    return @move.basedamage > 0 ? 1 : 0 if @opponent.ability == :STICKYHOLD && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))
    return @move.basedamage > 0 ? 1 : 0 if @opponent.item.nil? || @battle.pbIsUnlosableItem(@opponent, @opponent.item) || (@attacker.item && !([:TRICK,:SWITCHEROO].include?(@move.move)))
    return @move.basedamage > 0 ? 1 : 0 if @opponent.effects[:Substitute] > 0
    miniscore = 1.2
    case @opponent.item
      when :LEFTOVERS, :LIFEORB, :LUMBERRY, :SITRUSBERRY
        miniscore*=1.5
      when :ASSAULTVEST, :ROCKYHELMET, :MAGICALSEED, :SYNTHETICSEED, :TELLURICSEED, :ELEMENTALSEED
        miniscore*=1.3
      when :FOCUSSASH, :MUSCLEBAND, :WISEGLASSES, :EXPERTBELT, :WIDELENS
        miniscore*=1.2
      when :CHOICESCARF
        miniscore*=1.1 if !pbAIfaster?()
      when :CHOICEBAND
        miniscore*=1.1 if @attacker.attack>@attacker.spatk
      when :CHOICESPECS
        miniscore*=1.1 if @attacker.spatk>@attacker.attack
      when :BLACKSLUDGE
        miniscore*= @attacker.hasType?(:POISON) ? 1.5 : 0.5
      when :TOXICORB, :FLAMEORB, :LAGGINGTAIL, :IRONBALL, :STICKYBARB
        miniscore*=0.5
    end
    return miniscore
  end

  def bestowcode # Gen 9 Mod - Added myceliumMightCheck
    return 0 if ((@opponent.ability == :STICKYHOLD || @opponent.ability == :GOODASGOLD) && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker)))
    return 0 if @attacker.item.nil? || @battle.pbIsUnlosableItem(@attacker,@attacker.item) || (@opponent.item && !([:TRICK,:SWITCHEROO].include?(@move.move)))
    return 0 if @opponent.effects[:Substitute] > 0
    miniscore = 1.0
    case @attacker.item
      when :LEFTOVERS, :LIFEORB, :LUMBERRY, :SITRUSBERRY
        miniscore*=0.5
      when :FOCUSSASH, :MUSCLEBAND, :WISEGLASSES, :EXPERTBELT, :WIDELENS
        miniscore*=0.8
      when :ASSAULTVEST, :ROCKYHELMET, :MAGICALSEED, :SYNTHETICSEED, :TELLURICSEED, :ELEMENTALSEED
        miniscore*=0.7
      when :CHOICESPECS
        miniscore*=1.7 if @opponent.attack>@opponent.spatk
        miniscore*=0.8 if @attacker.attack<@attacker.spatk
      when :CHOICESCARF
        miniscore*= pbAIfaster?() ? 0.9 : 1.5
      when :CHOICEBAND
        miniscore*=1.7 if @opponent.attack<@opponent.spatk
        miniscore*=0.8 if @attacker.attack>@attacker.spatk
      when :BLACKSLUDGE
        miniscore*= @attacker.hasType?(:POISON) ? 0.5 : 1.5
        miniscore*=1.3 if !@opponent.hasType?(:POISON)
      when :TOXICORB, :FLAMEORB, :LAGGINGTAIL, :IRONBALL, :STICKYBARB
        miniscore*=1.5
    end
    if [:CHOICESCARF,:CHOICEBAND,:CHOICESPECS].include?(@attacker.item) #choice locking
      miniscore*=3 if @opponent.lastMoveUsed.is_a?(Symbol) && pbAIfaster?(@move) && $cache.moves[@opponent.lastMoveUsed].category == :status
      miniscore*=1.5 if hasbadmoves(40)
      miniscore*=1.5 if @battle.turncount == 1
      maxdam = checkAIdamage()
      miniscore*=0.3 if maxdam > 0.5 * @attacker.hp
      miniscore*=1.3 if maxdam < 0.33 * @attacker.hp
    end
    return miniscore
  end

  def recoilcode
    return @move.basedamage > 0 ? 1 : 0 if @attacker.ability == :ROCKHEAD || @attacker.crested == :RAMPARDOS || @attacker.ability == :MAGICGUARD || (@attacker.ability == :WONDERGUARD && @battle.FE == :COLOSSEUM)
    return @move.basedamage > 0 ? 1 : 0 if @move.move == :WILDCHARGE && @battle.FE == :ELECTERRAIN

    recoilamount = @move.recoil
    miniscore = 0.9
    miniscore *= 0.7 if notOHKO?(@attacker, @opponent, true)
    miniscore *= 0.8 if @attacker.hp > 0.1 * @attacker.totalhp && @attacker.hp < 0.4 * @attacker.totalhp
    miniscore *= 0.4 if @initial_scores[@score_index] * recoilamount > @attacker.hp && (@opponent.status == :SLEEP || (@opponent.status == :FROZEN && !KAIZOMOD))
    return miniscore
  end

  def weathercode
    if @battle.pbCheckGlobalAbility(:AIRLOCK) || @battle.pbCheckGlobalAbility(:CLOUDNINE) || @battle.pbCheckGlobalAbility(:DELTASTREAM) ||
      @battle.pbCheckGlobalAbility(:DESOLATELAND) || @battle.pbCheckGlobalAbility(:PRIMORDIALSEA) || @battle.pbCheckGlobalAbility(:TEMPEST)
      return @move.basedamage > 0 ? 1 : 0
    end
    return @move.basedamage > 0 ? 1 : 0 if [:NEWWORLD,:UNDERWATER].include?(@battle.FE)
    miniscore=1.0
    miniscore*=1.3 if notOHKO?(@attacker, @opponent, true)
    miniscore*=1.2 if @mondata.roles.include?(:LEAD)
    miniscore*=1.4 if @attacker.pbHasMove?(:WEATHERBALL)
    miniscore*=1.5 if @attacker.ability == :FORECAST
    return miniscore
  end

  def suncode
    return @move.basedamage > 0 ? 1 : 0 if @battle.pbWeather== :SUNNYDAY
    return @move.basedamage > 0 ? 1 : 0 if @battle.FE == :DIMENSIONAL
    miniscore=1.0
    miniscore*=0.2 if @attacker.ability == :FORECAST && (@opponent.hasType?(:GROUND) || @opponent.hasType?(:ROCK))
    miniscore*=1.3 if (@mondata.attitemworks && @attacker.item == :HEATROCK) || [:DESERT,:MOUNTAIN,:SNOWYMOUNTAIN,:SKY].include?(@battle.FE)
    miniscore*=1.5 if @battle.pbWeather!=0 && @battle.pbWeather!=:SUNNYDAY
    miniscore*=1.5 if @attacker.pbHasMove?(:MOONLIGHT) || @attacker.pbHasMove?(:SYNTHESIS) || @attacker.pbHasMove?(:MORNINGSUN) || @attacker.pbHasMove?(:GROWTH) || @attacker.pbHasMove?(:SOLARBEAM) || @attacker.pbHasMove?(:SOLARBLADE) || @attacker.pbHasMove?(:HYDROSTEAM) # Gen 9 Mod - Added Hydro Steam
    miniscore*=0.7 if checkAImoves([:SYNTHESIS, :MOONLIGHT, :MORNINGSUN])
    miniscore*=1.5 if @attacker.hasType?(:FIRE)
    if @attacker.ability == :CHLOROPHYLL || @attacker.ability == :FLOWERGIFT
      miniscore*=2
      miniscore*=2 if notOHKO?(@attacker, @opponent, true)
      miniscore*=3 if seedProtection?(@attacker)
    end
    miniscore*=1.3 if [:SOLARPOWER,:LEAFGUARD,:SOLARIDOL].include?(@attacker.ability)
    # Gen 9 Mod - Added Protosynthesis & Orichalcum Pulse
    miniscore*=1.5 if [:PROTOSYNTHESIS,:ORICHALCUMPULSE].include?(@attacker.ability)
    miniscore*=0.5 if pbPartyHasType?(:WATER)
    miniscore*=0.7 if @attacker.pbHasMove?(:THUNDER) || @attacker.pbHasMove?(:HURRICANE)
    miniscore*=0.5 if @attacker.ability == :DRYSKIN
    miniscore*=1.5 if @attacker.ability == :HARVEST
    return miniscore
  end

  def raincode
    return 0 if @battle.pbWeather== :RAINDANCE
    return @move.basedamage > 0 ? 1 : 0 if [:DIMENSIONAL,:INFERNAL].include?(@battle.FE)
    miniscore=1.0
    miniscore*=0.2 if @attacker.ability == :FORECAST && (@opponent.hasType?(:GRASS) || @opponent.hasType?(:ELECTRIC))
    miniscore*=1.3 if (@mondata.attitemworks && @attacker.item == :DAMPROCK) || [:BIGTOP,:SKY,:CLOUDS].include?(@battle.FE)
    miniscore*=1.3 if @battle.pbWeather!=0 && @battle.pbWeather!=:RAINDANCE
    # Gen 9 Mod - Added Electro Shot
    miniscore*=1.5 if @attacker.pbHasMove?(:THUNDER) || @attacker.pbHasMove?(:HURRICANE) || @attacker.pbHasMove?(:ELECTROSHOT)
    miniscore*=1.5 if @attacker.hasType?(:WATER)
    if @attacker.ability == :SWIFTSWIM
      miniscore*=2
      miniscore*=2 if notOHKO?(@attacker, @opponent, true)
      miniscore*=3 if seedProtection?(@attacker)
    end
    miniscore*=1.5 if @attacker.ability == :DRYSKIN || @battle.pbWeather== :RAINDANCE
    miniscore*=0.5 if pbPartyHasType?(:FIRE)
    miniscore*=0.5 if @attacker.pbHasMove?(:MOONLIGHT) || @attacker.pbHasMove?(:SYNTHESIS) || @attacker.pbHasMove?(:MORNINGSUN) || @attacker.pbHasMove?(:GROWTH) || @attacker.pbHasMove?(:SOLARBEAM) || @attacker.pbHasMove?(:SOLARBLADE)
    miniscore*=1.5 if @attacker.ability == :HYDRATION
    return miniscore
  end

  def sandcode
    return 0 if @battle.pbWeather== :SANDSTORM
    return @move.basedamage > 0 ? 1 : 0 if @battle.FE == :DIMENSIONAL
    miniscore = 1.0
    miniscore*=1.3 if (@mondata.attitemworks && @attacker.item == :SMOOTHROCK) || [:DESERT,:ASHENBEACH,:SKY].include?(@battle.FE)
    miniscore*=2 if @battle.pbWeather!=0 && @battle.pbWeather!=:SANDSTORM
    miniscore*= (@attacker.hasType?(:ROCK) || @attacker.hasType?(:GROUND) || @attacker.hasType?(:STEEL)) ? 1.3 : 0.7
    miniscore*=1.5 if @attacker.hasType?(:ROCK)
    if @attacker.ability == :SANDRUSH
      miniscore*=2
      miniscore*=2 if notOHKO?(@attacker, @opponent, true)
      miniscore*=3 if seedProtection?(@attacker)
    end
    miniscore*=1.3 if @attacker.ability == :SANDVEIL
    miniscore*=0.5 if @attacker.pbHasMove?(:MOONLIGHT) || @attacker.pbHasMove?(:SYNTHESIS) || @attacker.pbHasMove?(:MORNINGSUN) || @attacker.pbHasMove?(:GROWTH) || @attacker.pbHasMove?(:SOLARBEAM) || @attacker.pbHasMove?(:SOLARBLADE)
    miniscore*=1.5 if @attacker.pbHasMove?(:SHOREUP)
    miniscore*=1.5 if @attacker.ability == :SANDFORCE
    return miniscore
  end

  def hailcode
    return 0 if @battle.pbWeather== :HAIL
    return @move.basedamage > 0 ? 1 : 0 if [:SUPERHEATED,:VOLCANIC,:VOLCANICTOP,:INFERNAL].include?(@battle.FE)
    return @move.basedamage > 0 ? 1 : 0 if Rejuv && @battle.FE == :DRAGONSDEN
    miniscore=1.0
    miniscore*=0.2 if @attacker.ability == :FORECAST && [:ROCK,:FIRE,:STEEL,:FIGHTING].any? {|type| @opponent.hasType?(type) }
    miniscore*=1.3 if (@mondata.attitemworks && @attacker.item == :ICYROCK) || [:ICY,:SNOWYMOUNTAIN,:FROZENDIMENSION,:CLOUDS,:SKY].include?(@battle.FE)
    miniscore*=1.3 if @battle.pbWeather!=0 && @battle.pbWeather!=:HAIL
    miniscore*= (@attacker.hasType?(:ICE)) ? 5 : 0.7
    if @attacker.ability == :SLUSHRUSH || @attacker.crested == :EMPOLEON || (@attacker.crested == :CASTFORM && @attacker.form == 3)
      miniscore*=2
      miniscore*=2 if notOHKO?(@attacker, @opponent, true)
      miniscore*=3 if seedProtection?(@attacker)
    end
    miniscore*=1.3 if [:SNOWCLOAK,:ICEBODY,:LUNARIDOL].include?(@attacker.ability) || (@attacker.ability == :ICEFACE && @attacker.form == 1)
    miniscore*=0.5 if @attacker.pbHasMove?(:MOONLIGHT) || @attacker.pbHasMove?(:SYNTHESIS) || @attacker.pbHasMove?(:MORNINGSUN) || @attacker.pbHasMove?(:GROWTH) || @attacker.pbHasMove?(:SOLARBEAM) || @attacker.pbHasMove?(:SOLARBLADE)
    miniscore*=2 if @attacker.pbHasMove?(:AURORAVEIL)
    miniscore*=1.3 if @attacker.pbHasMove?(:BLIZZARD)
    return miniscore
  end

  def subcode
    return 0 if @attacker.hp * 4 <= @attacker.totalhp
    return 0 if @attacker.effects[:Substitute] > 0 && pbAIfaster?(@move)

    miniscore = 1.0
    miniscore *= (@attacker.hp == @attacker.totalhp) ? 1.1 : (@attacker.hp * (1.0 / @attacker.totalhp))
    miniscore *= 1.2 if @opponent.effects[:LeechSeed] >= 0
    miniscore *= 1.2 if hpGainPerTurn > 1
    miniscore *= 1.2 if @attacker.moves.any? { |moveloop| moveloop != nil && moveloop.isHealingMove? }
    miniscore *= 1.2 if checkAImoves([:SPORE, :SLEEPPOWDER])
    miniscore *= 1.5 if @attacker.pbHasMove?(:FOCUSPUNCH)
    miniscore *= 1.5 if @opponent.status == :SLEEP
    miniscore *= 0.3 if @opponent.ability == :INFILTRATOR
    # Gen 9 Mod - Added Clanging Scales, Overdrive, Torch Song and Psychic Noise
    miniscore *= 0.3 if checkAImoves([:UPROAR, :HYPERVOICE, :ECHOEDVOICE, :SNARL, :BUGBUZZ, :BOOMBURST, :SPARKLINGARIA, :CLANGINGSCALES, :OVERDRIVE, :TORCHSONG, :PSYCHICNOISE])
    miniscore *= 2   if checkAIdamage() * 4 < @attacker.totalhp && (getAIMemory().length > 0)
    miniscore *= 1.3 if @opponent.effects[:Confusion] > 0
    miniscore *= 1.3 if @opponent.status == :PARALYSIS
    miniscore *= 1.3 if @opponent.effects[:Attract] >= 0
    miniscore *= 1.2 if @attacker.pbHasMove?(:BATONPASS)
    miniscore *= 1.1 if @attacker.ability == :SPEEDBOOST
    miniscore *= 0.5 if @battle.doublebattle
    return miniscore
  end

  def futurecode
    return 0 if @opponent.effects[:FutureSight]>0
    miniscore=0.6
    miniscore*=0.7 if @battle.doublebattle
    miniscore*=0.7 if @attacker.pbNonActivePokemonCount==0
    miniscore*=1.2 if @attacker.effects[:Substitute]>0
    miniscore*=1.2 if @attacker.moves.any? {|moveloop| moveloop!=nil && [:PROTECT,:DETECT,:BANEFULBUNKER,:SPIKYSHIELD,:SILKTRAP,:BURNINGBULWARK].include?(moveloop.move) } # Gen 9 Mod - Added Silk Trap and Burning Bulwark
    miniscore*=1.1 if @mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL)
    miniscore*=1.2 if @attacker.ability == :MOODY || @attacker.pbHasMove?(:QUIVERDANCE) || @attacker.pbHasMove?(:NASTYPLOT) || @attacker.pbHasMove?(:TAILGLOW)
    return miniscore
  end

  def focuscode
    return 0 if @mondata.skill >= BESTSKILL && @battle.FE == :ELECTERRAIN
    miniscore=1.0
    soundcheck=getAIMemory().any? {|moveloop| moveloop!=nil && moveloop.isSoundBased? && moveloop.basedamage>0}
    multicheck=getAIMemory().any? {|moveloop| moveloop!=nil && moveloop.pbNumHits(@opponent)>1}
    if @attacker.effects[:Substitute]>0
      if multicheck || soundcheck || @opponent.ability == :INFILTRATOR
        miniscore*=0.9
      else
        miniscore*=1.3
      end
    else
      miniscore *= 0.8
    end
    miniscore*=1.2 if @opponent.status== :SLEEP && @opponent.ability != :EARLYBIRD && @opponent.ability != :SHEDSKIN
    miniscore*=0.5 if @battle.doublebattle
    miniscore*=1.5 if @opponent.effects[:HyperBeam]>0
    miniscore*=0.3 if miniscore<=1.0
    return miniscore
  end

  def suckercode
    miniscore=1.0
    return miniscore*1.3 if getAIMemory().length>=4 && getAIMemory().all? {|moveloop| moveloop!=nil && moveloop.basedamage>0}
    miniscore*=0.6 if checkAIhealing()
    miniscore*=0.8 if checkAImoves(PBStuff::SETUPMOVE)
    if @attacker.lastMoveUsed==:SUCKERPUNCH # Sucker Punch last turn
      miniscore*=0.3 if rand(3) != 1
      miniscore*=0.5 if checkAImoves(PBStuff::SETUPMOVE)
    end
    if pbAIfaster?()
      miniscore*=0.8
      miniscore*=0.6 if @initial_scores.length>0 && @initial_scores.max!=@initial_scores[@score_index]
    else
      miniscore*= checkAIpriority() ? 0.5 : 1.3
    end
    return miniscore
  end

  def followcode
    return 0 if !@battle.doublebattle || @attacker.pbPartner.hp==0
    return 0 if @opponent.ability == :PROPELLERTAIL || @opponent.ability == :STALWART
    miniscore=1.0
    miniscore*=1.2 if @mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL)
    miniscore*=1.3 if @attacker.pbPartner.ability == :MOODY
    miniscore*= (@attacker.pbPartner.turncount<1) ? 1.2 : 0.8
    miniscore*= 1.3 if @attacker.pbPartner.moves.any? {|moveloop| moveloop!=nil && (PBStuff::SETUPMOVE).include?(moveloop.move)}
    bestmove1,maxdam1 = checkAIMovePlusDamage(@attacker.pbOpposing1,@attacker.pbPartner)
    bestmove2,maxdam2 = checkAIMovePlusDamage(@attacker.pbOpposing2,@attacker.pbPartner)
    miniscore*=1.5 if notOHKO?(@attacker, @opponent, true)
    if maxdam1 >= @attacker.pbPartner.hp && pbRoughDamage(bestmove1,@attacker.pbOpposing1,@attacker) < 0.7*@attacker.hp ||
       maxdam2 >= @attacker.pbPartner.hp && pbRoughDamage(bestmove2,@attacker.pbOpposing2,@attacker) < 0.7*@attacker.hp
       miniscore*= 1.3
    end
    if @attacker.hp==@attacker.totalhp
      miniscore*=1.2
    else
      miniscore*=0.8
      miniscore*=0.5 if @attacker.hp*2 < @attacker.totalhp
    end
    miniscore*=1.2 if !pbAIfaster?() || !pbAIfaster?(nil,nil,@attacker,@opponent.pbPartner)
    return miniscore
  end

  def gravicode
    return 0 if @battle.state.effects[:Gravity] != 0
    return 0 if @attacker.moves.any? { |moveloop| moveloop != nil && [:SKYDROP, :BOUNCE, :FLY, :JUMPKICK, :FLYINGPRESS, :HIJUMPKICK].include?(moveloop.move) }

    miniscore = 1.0
    miniscore *= 2 if @attacker.moves.any? { |moveloop| moveloop != nil && moveloop.accuracy <= 70 }
    miniscore *= 2 if @attacker.pbPartner.pbHasMove?(:GRAVAPPLE)
    miniscore *= 3 if @attacker.pbHasMove?(:ZAPCANNON) || @attacker.pbHasMove?(:INFERNO)
    miniscore *= 2 if [:SKYDROP, :BOUNCE, :FLY, :JUMPKICK, :FLYINGPRESS, :HIJUMPKICK].include?(checkAIbestMove().move)
    miniscore *= 2 if @attacker.hasType?(:GROUND) && (@opponent.hasType?(:FLYING) || [:LEVITATE, :SOLARDIOL, :LUNARIDOL].include?(@opponent.ability) || (@mondata.oppitemworks && @opponent.item == :AIRBALLOON))
    return miniscore
  end

  def magnocode
    return 0 if @attacker.effects[:MagnetRise]!=0 || @attacker.effects[:Ingrain] || @attacker.effects[:SmackDown]

    miniscore = 1.0
    miniscore *= 3 if checkAIbestMove().pbType(@opponent) == :GROUND # Highest expected dam from a ground move
    miniscore *= 3 if @opponent.hasType?(:GROUND)
    return miniscore
  end

  def telecode
    return 0 if @opponent.effects[:Telekinesis] > 0 || @opponent.effects[:Ingrain] || @opponent.effects[:SmackDown] || @battle.state.effects[:Gravity] != 0
    return 0 if @opponent.species == :DIGLETT || @opponent.species == :DUGTRIO || @opponent.species == :SANDYGAST || @opponent.species == :PALOSSAND
    return 0 if (@opponent.species == :GENGAR && @opponent.form == 1) || @opponent.item == :IRONBALL

    score = @initial_scores[@score_index]
    score += 10 if @attacker.moves.any? { |moveloop| moveloop != nil && moveloop.accuracy <= 70 }
    score *= 2 if @attacker.pbHasMove?(:ZAPCANNON) || @attacker.pbHasMove?(:INFERNO)
    score *= 0.5 if @attacker.moves.any? { |moveloop| moveloop != nil && moveloop.pbType(@attacker) == :GROUND && moveloop.basedamage > 0 }
    miniscore = oppstatdrop([0, 2, 0, 0, 2, 0, 0]) if @battle.FE == :PSYTERRAIN
    score *= miniscore if miniscore && miniscore > 0
    return score
  end

  def afteryoucode
    return 1
  end

  def trcode
    return 0 if pbAIfaster?() && !(@mondata.attitemworks && @attacker.item == :IRONBALL)
    return 0 if opponent.hp > 0 && opponent.pokemon.piece == :KING
    miniscore=1.0
    miniscore*=1.3 if @mondata.partyroles.any? {|role| role.include?(:SWEEPER) }
    miniscore*=1.3 if @mondata.roles.include?(:TANK) || @mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL)
    miniscore*=1.5 if @mondata.roles.include?(:LEAD)
    miniscore*=1.3 if @battle.doublebattle
    miniscore*=1.5 if notOHKO?(@attacker, @opponent, true)
    if @opponent.pbPartner.hp > 0
      miniscore*=0.3 if @attacker.pbSpeed<pbRoughStat(@opponent,PBStats::SPEED) && @attacker.pbSpeed>pbRoughStat(@opponent.pbPartner,PBStats::SPEED)
      miniscore*=0.3 if @attacker.pbSpeed>pbRoughStat(@opponent,PBStats::SPEED) && @attacker.pbSpeed<pbRoughStat(@opponent.pbPartner,PBStats::SPEED)
    end
    if @battle.trickroom <= 0
      miniscore*=2
      miniscore*=6 if @initial_scores.length>0 && hasgreatmoves() #experimental -- cancels out drop if killing moves
    else
      miniscore*=1.3
    end
      return miniscore
  end

  def dinglenugget
    return 0 if checkAIdamage()>=@attacker.hp || @attacker.pbNonActivePokemonCount==0
    miniscore=1.3
    miniscore*=2 if @mondata.partyroles.any? {|role| role.include?(:SWEEPER) }
    miniscore*=2 if @attacker.pbNonActivePokemonCount<3
    miniscore*=0.5 if @attacker.pbOwnSide.effects[:StealthRock] || @attacker.pbOwnSide.effects[:Spikes]>0
    return miniscore
  end

  def wondercode
    return 0 if @battle.state.effects[:WonderRoom]!=0
    miniscore=1.0
    miniscore*=1.3 if (@mondata.attitemworks && @attacker.item == :AMPLIFIELDROCK) || @battle.FE == :NEWWORLD || @battle.FE == :PSYTERRAIN || (Rejuv && @battle.FE == :STARLIGHT)
    if pbRoughStat(@opponent,PBStats::ATTACK)>pbRoughStat(@opponent,PBStats::SPATK)
      miniscore*= (@attacker.defense>@attacker.spdef) ? 0.5 : 2
    else
      miniscore*= (@attacker.defense>@attacker.spdef) ? 2 : 0.5
    end
    if @attacker.attack>@attacker.spatk
      miniscore*= (pbRoughStat(@opponent,PBStats::DEFENSE)>pbRoughStat(@opponent,PBStats::SPDEF)) ? 2 : 0.5
    else
      miniscore*= (pbRoughStat(@opponent,PBStats::DEFENSE)>pbRoughStat(@opponent,PBStats::SPDEF)) ? 0.5 : 2
    end
    return miniscore
  end

  def lastcode
    return 0 unless @attacker.moves.all? {|moveloop| moveloop!=nil && (moveloop.function == 0x125 || @attacker.movesUsed.include?(moveloop.move)) }
    return 1
  end

  def powdercode
    return 0 if @opponent.hasType?(:GRASS) || @opponent.ability == :OVERCOAT || (@mondata.oppitemworks && @opponent.item == :SAFETYGOGGLES)
    return 0 if getAIMemory().length >= 4 && !getAIMemory().any? {|moveloop| moveloop!=nil && moveloop.pbType(@opponent)==:FIRE}
    # Gen 9 Mod - Discourage status moves when current opponent has Good as Gold
    return 0 if @opponent.ability == :GOODASGOLD && @move.category == :status && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))
    miniscore=1.0
    miniscore*=1.2 if !pbAIfaster?()
    if checkAIbestMove().pbType(@opponent) == :FIRE
      miniscore*=3
    else
      miniscore*= @opponent.hasType?(:FIRE) ? 2 : 0.2
    end
    effcheck = PBTypes.twoTypeEff((:FIRE),@attacker.type1,@attacker.type2)
    miniscore*=2 if effcheck>4
    miniscore*=2 if effcheck>8
    miniscore*=0.6 if @attacker.lastMoveUsed==:POWDER
    miniscore*=0.5 if @opponent.ability == :MAGICGUARD || (@opponent.ability == :WONDERGUARD && @battle.FE == :COLOSSEUM)
    return miniscore
  end

  def burnupcode
    return 0 if !@attacker.hasType?(:FIRE)
    miniscore= (1-@opponent.pbNonActivePokemonCount*0.05)
    if @initial_scores[@score_index]<100
      miniscore*=0.9
      miniscore*=0.5 if getAIMemory().any? {|moveloop| moveloop!=nil && moveloop.isHealingMove?}
    end
    miniscore*=0.5 if @initial_scores.length>0 && hasgreatmoves()
    miniscore*=0.7 if @attacker.pbNonActivePokemonCount==0 && @opponent.pbNonActivePokemonCount!=0
    effcheck = PBTypes.twoTypeEff(@opponent.type1,(:FIRE),(:FIRE))
    miniscore*=1.5 if effcheck > 4
    miniscore*=0.5 if effcheck < 4
      effcheck = PBTypes.twoTypeEff(@opponent.type2,(:FIRE),(:FIRE))
    miniscore*=1.5 if effcheck > 4
    miniscore*=0.5 if effcheck < 4
    effcheck = PBTypes.twoTypeEff(checkAIbestMove().pbType(@opponent),(:FIRE),(:FIRE))
    miniscore*=1.5 if effcheck > 4
    miniscore*=0.5 if effcheck < 4
    return miniscore
  end

  def beakcode
    miniscore = burncode
    miniscore*=0.7 if pbAIfaster?()
    if getAIMemory().any?{|moveloop| moveloop!=nil && moveloop.contactMove?}
      miniscore*=1.5
    elsif @opponent.attack>@opponent.spatk
      miniscore*=1.3
    else
      miniscore*=0.3
    end
    return miniscore
  end

  def moldbreakeronalaser
    return 1 if moldBreakerCheck(@attacker)
    damcount = @attacker.moves.count {|moveloop| moveloop!=nil && moveloop.basedamage>0}
    miniscore = 1.0
    case @opponent.ability
      when :SANDVEIL
        miniscore*=1.1 if @battle.pbWeather!=:SANDSTORM
      when :VOLTABSORB, :LIGHTNINGROD
        miniscore*=3 if @move.pbType(@attacker)==:ELECTRIC && damcount==1
        miniscore*=2 if @move.pbType(@attacker)==:ELECTRIC && PBTypes.twoTypeEff((:ELECTRIC),@opponent.type1,@opponent.type2)>4
      when :WATERABSORB, :STORMDRAIN, :DRYSKIN
        miniscore*=3 if @move.pbType(@attacker)==:WATER && damcount==1
        miniscore*=2 if @move.pbType(@attacker)==:WATER && PBTypes.twoTypeEff((:WATER),@opponent.type1,@opponent.type2)>4
        miniscore*=0.5 if @opponent.ability == :DRYSKIN && @attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.pbType(@attacker)==:FIRE}
      when :FLASHFIRE, :WELLBAKEDBODY # Gen 9 Mod - Added Well-Baked Body
        miniscore*=3 if @move.pbType(@attacker)==:FIRE && damcount==1
        miniscore*=2 if @move.pbType(@attacker)==:FIRE && PBTypes.twoTypeEff((:FIRE),@opponent.type1,@opponent.type2)>4
      when :LEVITATE, :LUNARIDOL, :SOLARIDOL, :EARTHEATER # Gen 9 Mod - Added Earth Eater
        miniscore*=3 if @move.pbType(@attacker)==:GROUND && damcount==1
        miniscore*=2 if @move.pbType(@attacker)==:GROUND && PBTypes.twoTypeEff((:GROUND),@opponent.type1,@opponent.type2)>4
      when :WONDERGUARD
        miniscore*=5
      when :SOUNDPROOF
        miniscore*=3 if @move.isSoundBased?
      when :THICKFAT
        miniscore*=1.5 if @move.pbType(@attacker)==:FIRE || move.pbType(@attacker)==:ICE
      when :MOLDBREAKER, :TURBOBLAZE, :TERAVOLT
        miniscore*=1.1
      when :UNAWARE
        miniscore*=1.7
      when :MULTISCALE
        miniscore*=1.5 if @attacker.hp==@attacker.totalhp
      when :TERASHELL # Gen 9 Mod - Tera Shell same consideration as Multiscale
        miniscore*=1.5 if @attacker.hp==@attacker.totalhp
      when :SAPSIPPER
        miniscore*=3 if @move.pbType(@attacker)==:GRASS && damcount==1
        miniscore*=2 if @move.pbType(@attacker)==:GRASS && PBTypes.twoTypeEff((:GRASS),@opponent.type1,@opponent.type2)>4
      when :SNOWCLOAK
        miniscore*=1.1 if @battle.pbWeather!=:HAIL
      when :FURCOAT
        miniscore*=1.5 if @attacker.attack>@attacker.spatk
      when :FLUFFY
        miniscore*=1.5
        miniscore*=0.5 if @move.pbType(@attacker)==:FIRE
      when :WATERBUBBLE
        miniscore*=1.5
        miniscore*=1.3 if @move.pbType(@attacker)==:FIRE
      when :WINDPOWER # Gen 9 Mod - Added Wind Power
        miniscore*=1.3 if @move.windMove? || @attacker.pbOwnSide.effects[:Tailwind] > 0
      when :WINDRIDER # Gen 9 Mod - Added Wind Rider
        miniscore*=3 if @move.windMove? || @attacker.pbOwnSide.effects[:Tailwind] > 0
      # when :MYCELIUMMIGHT # Gen 9 Mod - Added Mycelium Might
      #   miniscore*=2 if !(@move.pbIsPhysical?(opponent) || @move.pbIsSpecial?(opponent))
      when :ICESCALES
        miniscore*=1.5 if @attacker.spatk>@attacker.attack
    end
    return miniscore
  end

  def pussydeathcode(initialscore)
    return 0 if @move.move = :MINDBLOWN && @battle.pbCheckGlobalAbility(:DAMP)
    return 0 if @battle.FE == :FACTORY && @move.move == :STEELBEAM && (@attacker.ability != :MAGICGUARD && !(@attacker.ability == :WONDERGUARD && @battle.FE == :COLOSSEUM)) && @attacker.hp<@attacker.totalhp*0.25 || (@attacker.hp<@attacker.totalhp*0.5 && !pbAIfaster?())
    return 0 if (@attacker.ability != :MAGICGUARD && !(@attacker.ability == :WONDERGUARD && @battle.FE == :COLOSSEUM)) && @attacker.hp<@attacker.totalhp*0.5 || (@attacker.hp<@attacker.totalhp*0.75 && !pbAIfaster?())
    miniscore=1.0
    if @attacker.ability != :MAGICGUARD && !(@attacker.ability == :WONDERGUARD && @battle.FE == :COLOSSEUM)
      miniscore*=0.7
      miniscore*=0.7 if initialscore < 100
      miniscore*=0.5 if !pbAIfaster?()
      miniscore*=1.3 if checkAIdamage() < @attacker.totalhp*0.2
      miniscore*=1.2 if @attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.isHealingMove?}
      miniscore*=1.3 if @initial_scores.length>0 && hasbadmoves(25)
      miniscore*=0.5 if checkAImoves(PBStuff::PROTECTMOVE) && !(@move.contactMove? && unseenFistCheck(@attacker)) # Gen 9 Mod - Method that also checks Punching Glove
      miniscore*=(1-0.1*@opponent.stages[PBStats::EVASION])
      miniscore*=(1+0.1*@opponent.stages[PBStats::ACCURACY])
      miniscore*=0.7 if @mondata.oppitemworks && (@opponent.item == :LAXINCENSE || @opponent.item == :BRIGHTPOWDER)
      miniscore*=0.7 if accuracyWeatherAbilityActive?(@opponent)
    else
      miniscore*=1.1
    end
    return miniscore
  end

  def chopcode
    return 1 if secondaryEffectNegated?()
    miniscore=1.0
    if checkAIbestMove().isSoundBased?
      miniscore*=1.5
    elsif getAIMemory().any? {|moveloop| moveloop!=nil && moveloop.isSoundBased?}
      miniscore*=1.3
    end
    return miniscore
  end

  def shelltrapcode
    miniscore=1.0
    miniscore*=0.5 if pbAIfaster?()
    bestmove, maxdam = checkAIMovePlusDamage()
    if notOHKO?(@attacker, @opponent, true)
      miniscore*=1.2
    else
      miniscore*=0.8
      miniscore*=0.8 if maxdam>@attacker.hp
    end
    miniscore*=0.7 if @attacker.lastMoveUsed==:SHELLTRAP
    miniscore*=0.6 if checkAImoves(PBStuff::SETUPMOVE)
    miniscore*=@attacker.hp*(1.0/@attacker.totalhp)
    miniscore*=0.3 if @opponent.spatk > @opponent.attack
    miniscore*=0.05 if bestmove.pbIsSpecial?()
    return miniscore
  end

  def almostuselessmovecode
    return 0 if @opponent.index!=@attacker.pbPartner.index || @opponent.status.nil?
    miniscore=1.5
    if @opponent.hp>@opponent.totalhp*0.8
      miniscore*=0.8
    elsif @opponent.hp>@opponent.totalhp*0.3
      miniscore*=2
    end
    miniscore*=1.3 if @opponent.effects[:Toxic]>3
    # Gen 9 Mod - Additional Checks for Salt Cure
    miniscore*=1.1 if @opponent.effects[:SaltCure] && @opponent.ability != :MAGICGUARD
    miniscore*=1.1 if @opponent.effects[:SaltCure] && @opponent.ability != :MAGICGUARD && (@opponent.hasType?(:WATER) || @opponent.hasType?(:STEEL))
    miniscore*=1.3 if checkAImoves([:HEX])
    return miniscore
  end

  def psychicterraincode
    return @move.basedamage > 0 ? 1 : 0 if @battle.FE == :UNDERWATER || @battle.FE == :NEWWORLD || @battle.FE == :PSYTERRAIN || (Rejuv && @battle.FE == :DRAGONSDEN)
    if Rejuv && @battle.FE != :INDOOR
      return @move.basedamage > 0 ? 1 : 0 if @battle.state.effects[:PSYTERRAIN] > 0 || @battle.FE == :FROZENDIMENSION
      miniscore = 1.0
      miniscore*=1.5 if @attacker.hasType?(:PSYCHIC)
      miniscore*=2 if pbPartyHasType?(:PSYCHIC)
      miniscore*=0.5 if @opponent.hasType?(:PSYCHIC)
      miniscore*=1.5 if @attacker.ability == :FOREWARN || @attacker.ability == :ANTICIPATION
      miniscore*=0.7  if @attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.pbIsPriorityMoveAI(@attacker)} && @attacker.isAirborne?
      miniscore*=2  if (@mondata.attitemworks && @attacker.item == :AMPLIFIELDROCK)
    else
      miniscore = getFieldDisruptScore(@attacker,@opponent)
      miniscore*=1.5 if @attacker.ability == :TELEPATHY
      miniscore*=1.5 if @attacker.hasType?(:PSYCHIC)
      miniscore*=2 if pbPartyHasType?(:PSYCHIC)
      miniscore*=0.5 if @opponent.hasType?(:PSYCHIC)
      miniscore*=1.5 if @attacker.ability == :ANTICIPATION
      miniscore*=0.7  if @attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.pbIsPriorityMoveAI(@attacker)} && @attacker.isAirborne?
      miniscore*=1.3 if checkAIpriority() && !@opponent.isAirborne?
      miniscore*=2  if (@mondata.attitemworks && @attacker.item == :AMPLIFIELDROCK)
    end
    return miniscore
  end

  def instructcode # function is only evaluated for the partner, never the opponent
    miniscore=3.0
    if @opponent.hp < 0.5*@opponent.totalhp
      miniscore*=0.5
    elsif @opponent.hp==@opponent.totalhp
      miniscore*=1.2
    end
    miniscore*=1.2 if @initial_scores.length>0 && hasbadmoves(20)
    lastmove = @attacker.pbPartner.lastMoveUsed
    lastmove = PokeBattle_Move.pbFromPBMove(@battle,PBMove.new(lastmove),@attacker.pbPartner)
    lastmovetarget = @attacker.pbPartner.lastMoveChoice[3]
    lastmovetarget = firstOpponent() if lastmovetarget == -1
    movescore = pbRoughDamage(lastmove, @attacker.pbPartner, @battle.battlers[lastmovetarget])
    if movescore == 0
      miniscore*=0
    elsif movescore > @battle.battlers[lastmovetarget].hp
      miniscore*=1.5
    end

    miniscore*=1.4 if !pbAIfaster?(nil, nil, @attacker.pbPartner, @attacker.pbOpposing1) && !pbAIfaster?(nil, nil, @attacker.pbPartner, @attacker.pbOpposing2)
    miniscore*= (1 + ([@opponent.attack,@opponent.spatk].max - [@attacker.attack,@attacker.spatk].max)/100.0)
    return miniscore
  end

  def antistatcode(stats,beginscore)
    miniscore=1.0
    miniscore*=(1-0.05*(@opponent.pbNonActivePokemonCount-2)) if @opponent.pbNonActivePokemonCount > 0
    miniscore*=1.2 if !@battle.doublebattle && @mondata.partyroles.any? {|role| role.include?(:PIVOT) }
    miniscore*=0.7 if @initial_scores.length>0 && hasgreatmoves()
    miniscore*=0.9 if beginscore < 100
    stats.unshift(0)
    for i in 0...stats.length
      next if stats[i].nil? || stats[i]==0
      case i
        when PBStats::ATTACK
          miniscore*=0.5 if beginscore < 100 && checkAIhealing()
          miniscore*=0.8 if @opponent.pbNonActivePokemonCount > 0 && @attacker.pbNonActivePokemonCount==0
        when PBStats::DEFENSE
          miniscore/=0.9 if beginscore < 100 && !pbAIfaster?() || checkAIpriority()
          miniscore/=0.9 if beginscore < 100 && @opponent.attack < @opponent.spatk
          miniscore*=0.8 if @mondata.roles.include?(:PHYSICALWALL)
        when PBStats::SPEED
          miniscore*=1.1 if @mondata.roles.include?(:TANK)
          miniscore*=0.8 if @attacker.pbSpeed>pbRoughStat(@opponent,PBStats::SPEED)
        when PBStats::SPATK
          miniscore*=0.5 if beginscore < 100 && checkAIhealing()
          miniscore*=0.8 if @opponent.pbNonActivePokemonCount > 0 && @attacker.pbNonActivePokemonCount==0
        when PBStats::SPDEF
          miniscore/=0.9 if !pbAIfaster?() || checkAIpriority()
          miniscore/=0.9 if beginscore < 100 && @opponent.attack > @opponent.spatk
          miniscore*=0.9 if @mondata.roles.include?(:SPECIALWALL)
      end
    end
    return miniscore
  end

  def smackcode
    return 1 if @opponent.effects[:Ingrain] || @opponent.effects[:SmackDown] || @battle.state.effects[:Gravity]!=0 || (@mondata.oppitemworks && @opponent.item == :IRONBALL) || @opponent.effects[:Substitute]>0
    miniscore=1.0
    if !pbAIfaster?()
      if checkAImoves([:BOUNCE, :FLY, :SKYDROP])
        miniscore*=1.3
      else
        miniscore*=2 if @opponent.effects[:TwoTurnAttack]!=0
      end
    end
    if (@opponent.hasType?(:FLYING) || [:LEVITATE,:SOLARDIOL,:LUNARIDOL].include?(@opponent.ability))
      miniscore*= (@attacker.moves.any?{|moveloop| moveloop!=nil && moveloop.pbType(@attacker)==:GROUND && moveloop.basedamage>0}) ? 2 : 1.2
    end
    return miniscore
  end

  def nightmarecode
    return 0 if @opponent.effects[:Nightmare] || (@opponent.status!=:SLEEP && @battle.FE != :INFERNAL) || @opponent.effects[:Substitute]>0
    miniscore=1.0
    miniscore*=4 if @opponent.statusCount>2
    miniscore*=6 if @opponent.ability == :COMATOSE
    miniscore*=6 if @initial_scores.length>0 && hasbadmoves(25)
    miniscore*=0.5 if @opponent.ability == :SHEDSKIN || @opponent.ability == :EARLYBIRD
    if PBStuff::TRAPPINGABILITIESAI.include?(@attacker.ability) || (@attacker.ability == :MAGNETPULL && @opponent.hasType?(:STEEL))  || @opponent.effects[:MeanLook]>=0 || @opponent.pbNonActivePokemonCount==0
      miniscore*=1.3
    else
      miniscore*=0.8
    end
    miniscore*=0.5 if @battle.doublebattle
    return miniscore
  end

  def spitecode(score)
    score+=10 if !$cache.moves[@opponent.lastMoveUsed].nil? && $cache.moves[@opponent.lastMoveUsed].basedamage>0 && (@opponent.moves.count {|moveloop| moveloop!=nil && moveloop.basedamage>0}) ==1
    score*=0.5 if !pbAIfaster?(@move)
    if !$cache.moves[@opponent.lastMoveUsed].nil? && $cache.moves[@opponent.lastMoveUsed].maxpp==5
      score*=1.5
    elsif !$cache.moves[@opponent.lastMoveUsed].nil? && $cache.moves[@opponent.lastMoveUsed].maxpp==10
      score*=1.2
    else
      score*=0.7
    end
    return score
  end

  def spoopycode
    return @move.basedamage > 0 ? 1 : 0 if @opponent.effects[:Curse] || (((@attacker.hp*2<@attacker.totalhp && @battle.FE != :HAUNTED) || (@attacker.hp*4<@attacker.totalhp)) && @move.function == 0x10d)
    miniscore=0.7
    miniscore*=0.5 if !pbAIfaster?(@move)
    miniscore*=1.3 if (getAIMemory().length > 0) && checkAIdamage()*5 < @attacker.hp if @move.function == 0x10d
    miniscore*=1.2 if @attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.isHealingMove?}
    miniscore*=(1+0.05*statchangecounter(@opponent,1,7))
    if PBStuff::TRAPPINGABILITIESAI.include?(@attacker.ability) || (@attacker.ability == :MAGNETPULL && @opponent.hasType?(:STEEL))  || @opponent.effects[:MeanLook]>=0 || @opponent.pbNonActivePokemonCount==0
      miniscore*=1.3
    else
      miniscore*=0.8
    end
    miniscore*=0.5 if @battle.doublebattle
    miniscore*=1.3 if @initial_scores.length>0 && hasbadmoves(25)
    return miniscore
  end

  def brickbreakcode(attacker=@attacker)
    miniscore = 1.0
    miniscore*=1.8 if attacker.pbOpposingSide.effects[:Reflect]>0
    miniscore*=1.3 if attacker.pbOpposingSide.effects[:LightScreen]>0
    miniscore*=2.0 if attacker.pbOpposingSide.effects[:AuroraVeil]>0
    miniscore*=1.3 if attacker.pbOpposingSide.effects[:AreniteWall]>0
    return miniscore
  end

  def jumpcode(score)
    miniscore=1.0
    miniscore*= 0.8 if score < 100
    miniscore*=0.5 if checkAImoves(PBStuff::PROTECTMOVE) && !(@move.contactMove? && unseenFistCheck(@attacker)) # Gen 9 Mod - Method that also checks Punching Glove
    miniscore*=(1-0.1*@opponent.stages[PBStats::EVASION])
    miniscore*=(1+0.1*@attacker.stages[PBStats::ACCURACY])
    miniscore*=0.7 if accuracyWeatherAbilityActive?(@opponent)
    miniscore*=0.7 if (@mondata.oppitemworks && @opponent.item == :LAXINCENSE) || (@mondata.oppitemworks && @opponent.item == :BRIGHTPOWDER)
    return miniscore
  end

  def hazardcode
    miniscore = 1.0
    miniscore *= 1.1 if @mondata.roles.include?(:LEAD)
    miniscore *= 1.3 if notOHKO?(@attacker, @opponent)
    miniscore *= 1.2 if @attacker.turncount < 2
    miniscore *= 0.9 if @attacker.stages[PBStats::ATTACK] > 0 || @attacker.stages[PBStats::SPATK] > 0 && @move.basedamage == 0
    if @move.basedamage == 0
      if @opponent.pbNonActivePokemonCount > 2
        miniscore *= 0.2 * @opponent.pbNonActivePokemonCount
      else
        miniscore *= 0.2
      end
    end
    if @mondata.skill >= BESTSKILL
      if !@battle.pbIsWild?
        oppparty = @aiMoveMemory[@battle.pbGetOwner(@opponent.index)]
        movecheck = false
        for key in oppparty.keys
          movecheck = true if oppparty[key].any? { |moveloop| moveloop != nil && (moveloop.move == :DEFOG || moveloop.move == :RAPIDSPIN) }
        end
        miniscore *= 0.3 if (movecheck || checkAImovesAllOpponents([:DEFOG, :RAPIDSPIN])) && @move.basedamage == 0
      end
    elsif @mondata.skill >= MEDIUMSKILL
      miniscore *= 0.3 if checkAImovesAllOpponents([:DEFOG, :RAPIDSPIN]) && @move.basedamage == 0
    end
    return miniscore
  end

  def electricterraincode
    return @move.basedamage > 0 ? 1 : 0 if @battle.FE == :ELECTERRAIN || @battle.FE == :UNDERWATER || @battle.FE == :NEWWORLD || (Rejuv && @battle.FE == :DRAGONSDEN)
    if Rejuv && @battle.FE != :INDOOR
      return @move.basedamage > 0 ? 1 : 0 if @battle.state.effects[:ELECTERRAIN] > 0 || @battle.FE == :FROZENDIMENSION
      miniscore = 1
      miniscore*=1.5 if @attacker.ability == :SURGESURFER
      miniscore*=1.3 if @attacker.hasType?(:ELECTRIC)
      miniscore*=1.5 if pbPartyHasType?(:ELECTRIC)
      miniscore*=0.5 if @opponent.hasType?(:ELECTRIC)
      miniscore*=0.5 if @attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.function==0x03}
      miniscore*=1.6 if checkAImoves(PBStuff::SLEEPMOVE)
      miniscore*=2 if @mondata.attitemworks && @attacker.item == :AMPLIFIELDROCK
      miniscore*=3 if @attacker.ability == :HADRONENGINE # Gen 9 Mod - Added Hadron Engine
    else
      miniscore = getFieldDisruptScore(@attacker,@opponent)
      miniscore*=1.5 if @attacker.ability == :SURGESURFER
      miniscore*=1.3 if @attacker.hasType?(:ELECTRIC)
      miniscore*=1.5 if pbPartyHasType?(:ELECTRIC)
      miniscore*=0.5 if @opponent.hasType?(:ELECTRIC)
      miniscore*=0.5 if @attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.function==0x03}
      miniscore*=1.6 if checkAImoves(PBStuff::SLEEPMOVE)
      miniscore*=2 if @mondata.attitemworks && @attacker.item == :AMPLIFIELDROCK
      miniscore*=3 if @attacker.ability == :HADRONENGINE # Gen 9 Mod - Added Hadron Engine
    end
    return miniscore
  end

  def grassyterraincode
    return @move.basedamage > 0 ? 1 : 0 if @battle.FE == :GRASSY || @battle.FE == :UNDERWATER || @battle.FE == :NEWWORLD || (Rejuv && @battle.FE == :DRAGONSDEN)
    if Rejuv && @battle.FE != :INDOOR
      return @move.basedamage > 0 ? 1 : 0 if @battle.state.effects[:GRASSY] > 0 || @battle.FE == :FROZENDIMENSION
      miniscore = 1
      miniscore*=1.5 if @mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL)
      miniscore*=1.5 if @attacker.hasType?(:GRASS)
      miniscore*=2 if pbPartyHasType?(:GRASS)
      miniscore*=0.5 if checkAIhealing()
      miniscore*=1.5 if @attacker.ability == :GRASSPELT
      miniscore*=2 if @mondata.attitemworks && @attacker.item == :AMPLIFIELDROCK
    else
      miniscore = getFieldDisruptScore(@attacker,@opponent)
      miniscore*=1.5 if @mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL)
      miniscore*=1.5 if @attacker.hasType?(:FIRE)
      miniscore*=1.5 if pbPartyHasType?(:FIRE)
      if opponent.hasType?(:FIRE)
        miniscore*=0.5
        miniscore*=0.5 if @battle.pbWeather!=:RAINDANCE
        miniscore*=0.5 if @attacker.hasType?(:GRASS)
      elsif @attacker.hasType?(:GRASS)
        miniscore*=1.5
      end
      miniscore*=2 if pbPartyHasType?(:GRASS)
      miniscore*=0.5 if checkAIhealing()
      miniscore*=0.5 if checkAImoves([:SLUDGEWAVE])
      miniscore*=1.5 if @attacker.ability == :GRASSPELT
      miniscore*=2 if @mondata.attitemworks && @attacker.item == :AMPLIFIELDROCK
    end
    return miniscore
  end

  def mistyterraincode
    return 0 if @battle.FE == :MISTY || @battle.FE == :UNDERWATER || @battle.FE == :NEWWORLD || (Rejuv && @battle.FE == :DRAGONSDEN)
    if Rejuv && @battle.FE != :INDOOR
      return @move.basedamage > 0 ? 1 : 0 if @battle.state.effects[:MISTY] > 0 || @battle.FE == :FROZENDIMENSION
      miniscore = 1
      miniscore*=2 if pbPartyHasType?(:FAIRY)
      miniscore*=2 if !@attacker.hasType?(:FAIRY) && @opponent.hasType?(:DRAGON)
      miniscore*=0.5 if @attacker.hasType?(:DRAGON)
      miniscore*=0.5 if @opponent.hasType?(:FAIRY)
      miniscore*=2 if @attacker.hasType?(:FAIRY) && @opponent.spatk>@opponent.attack
      miniscore*=2 if @mondata.attitemworks && @attacker.item == :AMPLIFIELDROCK
    else
      miniscore = getFieldDisruptScore(@attacker,@opponent)
      miniscore*=2 if pbPartyHasType?(:FAIRY)
      miniscore*=2 if !@attacker.hasType?(:FAIRY) && @opponent.hasType?(:DRAGON)
      miniscore*=0.5 if @attacker.hasType?(:DRAGON)
      miniscore*=0.5 if @opponent.hasType?(:FAIRY)
      miniscore*=2 if @attacker.hasType?(:FAIRY) && @opponent.spatk>@opponent.attack
      miniscore*=2 if @mondata.attitemworks && @attacker.item == :AMPLIFIELDROCK
    end
    return miniscore
  end

  def arocode(stat)
    return 0 if !(@battle.doublebattle && @opponent.index==@attacker.pbPartner.index && @opponent.stages[stat]!=6)
    miniscore=1.0
    newopp = @attacker.pbOppositeOpposing
    miniscore*= newopp.spatk > newopp.attack ? 2 : 0.5
    miniscore*=1.3 if @initial_scores.length>0 && hasbadmoves(20)
    miniscore*=1.1 if @opponent.hp*(1.0/@opponent.totalhp)>0.75
    miniscore*=0.3 if @opponent.effects[:Yawn]>0 || @opponent.effects[:LeechSeed]>=0 || @opponent.effects[:Attract]>=0 || !@opponent.status.nil?
    if !@battle.pbIsWild?
      oppparty = @aiMoveMemory[@battle.pbGetOwner(newopp.index)]
      movecheck = false
      for key in oppparty.keys
        movecheck = true if oppparty[key].any? {|moveloop| moveloop!=nil && PBStuff::PHASEMOVE.include?(moveloop.move)}
      end
    end
    miniscore*=0.2 if movecheck
    miniscore*=2  if @opponent.ability == :SIMPLE
    miniscore*=0.5 if newopp.ability == :UNAWARE
    miniscore*=1.2 if hpGainPerTurn>1
    miniscore*=0 if @opponent.ability == :CONTRARY
    miniscore*=2 if @battle.FE == :MISTY && stat==PBStats::SPDEF
  end

  def flowershieldcode(score)
    return 0 unless @battle.doublebattle && @opponent.hasType?(:GRASS) && @opponent.index==@attacker.pbPartner.index && @opponent.stages[PBStats::DEFENSE]!=6
    opp1 = @attacker.pbOppositeOpposing
    opp2 = opp1.pbPartner
    if !@battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN,2,5)
      score*= opp1.attack>opp1.spatk ? 2 : 0.5
      score*= opp2.attack>opp2.spatk ? 2 : 0.5
    else
      score*=2
    end
    score+=30 if @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN,1,4)
    if @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN,2,5)|| @battle.FE == :FAIRYTALE
      score+=20
      miniscore=100
      miniscore*=1.3 if @attacker.effects[:Substitute]>0 || ((@attacker.effects[:Disguise] || (@attacker.effects[:IceFace] && (@opponent.attack > @opponent.spatk || @battle.FE == :FROZENDIMENSION))) && !moldBreakerCheck(@opponent))
      miniscore*=1.3 if @initial_scores.length>0 && hasbadmoves(20)
      miniscore*=1.1 if (@opponent.hp.to_f)/@opponent.totalhp>0.75
      miniscore*=1.2 if opp1.effects[:HyperBeam]>0
      miniscore*=1.3 if opp1.effects[:Yawn]>0
      miniscore*=1.1 if checkAIdamage() < @opponent.hp*0.3
      miniscore*=1.1 if @opponent.turncount<2
      miniscore*=1.1 if !opp1.status.nil?
      miniscore*=1.3 if opp1.status== :SLEEP || (opp1.status== :FROZEN && !KAIZOMOD)
      miniscore*=1.5 if opp1.effects[:Encore]>0 && opp1.moves[(opp1.effects[:EncoreIndex])].basedamage==0
      miniscore*=0.5 if @opponent.effects[:Confusion]>0
      miniscore*=0.3 if @opponent.effects[:LeechSeed]>=0 || @attacker.effects[:Attract]>=0
      miniscore*=0.2 if @opponent.effects[:Toxic]>0
      # Gen 9 Mod - Additional Checks for Salt Cure similar to the the toxic check above.
      miniscore*=0.6 if @opponent.effects[:SaltCure] && @opponent.ability != :MAGICGUARD
      miniscore*=0.6 if @opponent.effects[:SaltCure] && @opponent.ability != :MAGICGUARD && (@opponent.hasType?(:WATER) || @opponent.hasType?(:STEEL))
      miniscore*=0.2 if checkAImoves(PBStuff::PHASEMOVE)
      miniscore*=2 if @opponent.ability == :SIMPLE
      miniscore*=0.5 if opp1.ability == :UNAWARE
      miniscore*=0.3 if @battle.doublebattle
      miniscore/=100.0
      score*=miniscore
      miniscore=100
      miniscore*=1.5 if @mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL)
      miniscore*=1.2 if (@mondata.attitemworks && @attacker.item == :LEFTOVERS) || ((@mondata.attitemworks && @attacker.item == :BLACKSLUDGE) && @attacker.hasType?(:POISON))
      miniscore*=1.7 if @attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.isHealingMove?}
      miniscore*=1.3 if @attacker.pbHasMove?(:LEECHSEED)
      miniscore*=1.2 if @attacker.pbHasMove?(:PAINSPLIT)
      score*=miniscore if @attacker.stages[PBStats::SPDEF]!=6 && @attacker.stages[PBStats::DEFENSE]!=6
      score=0 if @attacker.ability == :CONTRARY
    end
    return score
  end

  def rotocode(score)
    return 0 unless @battle.doublebattle && @opponent.index == @attacker.pbPartner.index
    return 0 if !(@battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN,2,5)) && (!@opponent.hasType?(:GRASS) || @opponent.isAirborne?)
    miniscore = 1.0
    if @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN,2,5) && @attacker.hasType?(:GRASS) && !@attacker.isAirborne?
      score+=30
      miniscore*= selfstatboost([2,0,0,2,0,0,0])
    end
    if @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN)
      score+=20
      miniscore*=1.3 if @attacker.effects[:Substitute]>0 || ((@attacker.effects[:Disguise] || (@attacker.effects[:IceFace] && (@opponent.attack > @opponent.spatk || @battle.FE == :FROZENDIMENSION))) && !moldBreakerCheck(@opponent))
      miniscore*=1.3 if @initial_scores.length>0 && hasbadmoves(20)
      miniscore*=1.1 if (@opponent.hp.to_f)/@opponent.totalhp>0.75
      miniscore*=1.2 if opp1.effects[:HyperBeam]>0
      miniscore*=1.3 if opp1.effects[:Yawn]>0
      miniscore*=1.1 if checkAIdamage() < @opponent.hp*0.25
      miniscore*=1.1 if @opponent.turncount<2
      miniscore*=1.1 if !opp1.status.nil?
      miniscore*=1.3 if opp1.status== :SLEEP || (opp1.status== :FROZEN && !KAIZOMOD)
      miniscore*=1.5 if opp1.effects[:Encore]>0 && opp1.moves[(opp1.effects[:EncoreIndex])].basedamage==0
      miniscore*=0.2 if @opponent.effects[:Confusion]>0
      miniscore*=0.6 if @opponent.effects[:LeechSeed]>=0 || @attacker.effects[:Attract]>=0
      miniscore*=0.5 if checkAImoves(PBStuff::PHASEMOVE)
      miniscore*=2   if @opponent.ability == :SIMPLE
      miniscore*=0.5 if opp1.ability == :UNAWARE
      miniscore*=0.3 if @battle.doublebattle
      miniscore*=1+0.05*@opponent.stages[PBStats::SPEED] if @opponent.stages[PBStats::SPEED]<0
      ministat=@opponent.stages[PBStats::ATTACK] + @opponent.stages[PBStats::SPEED] + @opponent.stages[PBStats::SPATK]
      miniscore*=1 -0.05*ministat if ministat > 0
      miniscore*=1.3 if checkAIhealing()
      miniscore*=1.5 if @attacker.pbSpeed>pbRoughStat(@opponent,PBStats::SPEED,@mondata.skill) && @battle.trickroom==0
      miniscore*=1.3 if @mondata.roles.include?(:SWEEPER)
      miniscore*=0.5 if @attacker.status== :PARALYSIS
      miniscore*=0.3 if checkAImoves([:FOULPLAY])
      miniscore*=1.4 if @attacker.hp==@attacker.totalhp && (@mondata.attitemworks && @attacker.item == :FOCUSSASH)
      miniscore*=0.4 if checkAIpriority()
      score*=miniscore
    end
    return score
  end

  def craftyshieldcode(score)
    if attacker.lastMoveUsed==:CRAFTYSHIELD
      score*=0.5
    else
      score+=10 if opponent.moves.all? {|moveloop| moveloop!=nil && moveloop.basedamage>0}
      score*=1.5 if attacker.hp==attacker.totalhp
    end
    if @battle.FE == :FAIRYTALE
      score+=25
      score*=selfstatboost([0,1,0,0,1,0,0])
    end
    return score
  end

  def turvycode
    miniscore = [(1 + 0.10*statchangecounter(@opponent,1,7)),0].max
    miniscore = 2-miniscore if @opponent.index == @attacker.pbPartner.index
    return miniscore
  end

  def fairylockcode
    return 0 if @attacker.effects[:PerishSong]==1 || @attacker.effects[:PerishSong]==2
     miniscore=1.0
    miniscore*=10 if @opponent.effects[:PerishSong]==2
    miniscore*=20 if @opponent.effects[:PerishSong]==1
    miniscore*=0.8 if @attacker.effects[:LeechSeed]>=0
    miniscore*=1.2 if @opponent.effects[:LeechSeed]>=0
    miniscore*=1.3 if @opponent.effects[:Curse]
    miniscore*=0.7 if @attacker.effects[:Curse]
    miniscore*=1.1 if @opponent.effects[:Confusion]>0
    miniscore*=1.1 if @attacker.effects[:Confusion]>0
    return miniscore
  end

  def flingcode
     return 0 if @attacker.item.nil? || @battle.pbIsUnlosableItem(@attacker, @attacker.item) || @attacker.ability == :KLUTZ ||
                (pbIsBerry?(@attacker.item) && [:UNNERVE, :ASONECHILLING, :ASONEGRIM].include?(@opponent.ability)) ||
                @attacker.effects[:Embargo] > 0 || @attacker.pbOwnSide.effects[:EmbargoSide] > 0 || @battle.state.effects[:MagicRoom] > 0

    miniscore = 1.0
    case @attacker.item
      when :POISONBARB then miniscore *= 1.2 if @opponent.pbCanPoison?(false) && @opponent.ability != :POISONHEAL && @opponent.crested != :ZANGOOSE
      when :TOXICORB
        if @opponent.pbCanPoison?(false) && @opponent.ability != :POISONHEAL && @opponent.crested != :ZANGOOSE
          miniscore *= 1.2
          miniscore *= 2 if @attacker.pbCanPoison?(false) && @attacker.ability != :POISONHEAL
        end
      when :FLAMEORB
        if @opponent.pbCanBurn?(false) && @opponent.ability != :GUTS
          miniscore *= 1.3
          miniscore *= 2 if @attacker.pbCanBurn?(false) && @attacker.ability != :GUTS
        end
      when :LIGHTBALL then miniscore *= 1.3 if @opponent.pbCanParalyze?(false) && @opponent.ability != :QUICKFEET
      when :KINGSROCK, :RAZORCLAW then miniscore *= 1.3 if @opponent.ability != :INNERFOCUS && pbAIfaster?(@move)
      when :LAXINCENSE, :CHOICESCARF, :CHOICEBAND, :CHOICESPECS, :SYNTHETICSEED, :TELLURICSEED, :ELEMENTALSEED, :MAGICALSEED, :EXPERTBELT, :FOCUSSASH, :LEFTOVERS, :MUSCLEBAND, :WISEGLASSES, :LIFEORB, :EVIOLITE, :ASSAULTVEST, :BLACKSLUDGE, :POWERHERB, :MENTALHERB
        miniscore *= 0
      when :STICKYBARB then miniscore *= 1.2
      when :LAGGINGTAIL then miniscore *= 3
      when :IRONBALL then miniscore *= 1.5
    end
    if !@attacker.item.nil? && pbIsBerry?(@attacker.item)
      if @attacker.item == :FIGYBERRY || @attacker.item == :WIKIBERRY || @attacker.item == :MAGOBERRY || @attacker.item == :AGUAVBERRY || @attacker.item == :IAPAPABERRY
        miniscore *= 1.3 if @opponent.pbCanConfuseSelf?(false)
      else
        miniscore *= 0
      end
    end
    return miniscore
  end

  def recyclecode
    return 0 if @attacker.pokemon.itemRecycle.nil?
    return 0 if (@opponent.ability == :MAGICIAN && @opponent.item.nil?) || checkAImoves([:KNOCKOFF, :THIEF, :COVET])
    return 0 if @attacker.ability == :UNBURDEN || @attacker.ability == :HARVEST || @attacker.pbHasMove?(:ACROBATICS)

    miniscore = 2.0
    miniscore *= 2 if @attacker.pbHasMove?(:NATURALGIFT)
    case @attacker.pokemon.itemRecycle
      when :LUMBERRY
        miniscore *= 2 if !@attacker.status.nil?
      when :SITRUSBERRY, :FIGYBERRY, :WIKIBERRY, :MAGOBERRY, :AGUAVBERRY, :IAPAPABERRY
        miniscore *= 1.6 if @attacker.hp < 0.66 * @attacker.totalhp
        miniscore *= 1.5 if @mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL)
    end

    if !@attacker.item.nil? && pbIsBerry?(@attacker.pokemon.itemRecycle)
      miniscore *= 0 if [:UNNERVE, :ASONECHILLING, :ASONEGRIM].include?(@opponent.ability)
      miniscore *= 0 if checkAImoves([:INCINERATE, :PLUCK, :BUGBITE])
    end
    return miniscore
  end

  def embarcode(opponent = @opponent)
    return 0 if !KAIZOMOD && opponent.effects[:Embargo] > 0 && opponent.effects[:Substitute] > 0 || opponent.item.nil?
    return 0 if KAIZOMOD && opponent.pbOwnSide.effects[:EmbargoSide] > 0

    miniscore = 1.1
    # Gen 9 Mod - Discourage status moves when current opponent has Good as Gold
    miniscore *= 0 if @opponent.ability == :GOODASGOLD && @move.category == :status && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))
    miniscore *= 1.1 if !opponent.item.nil? && pbIsBerry?(opponent.item)
    case opponent.item
      when :LAXINCENSE, :SYNTHETICSEED, :TELLURICSEED, :ELEMENTALSEED, :MAGICALSEED, :EXPERTBELT, :MUSCLEBAND, :WISEGLASSES, :LIFEORB, :EVIOLITE, :ASSAULTVEST
        miniscore *= 1.2
      when :LEFTOVERS, :BLACKSLUDGE
        miniscore *= 1.3
    end
    miniscore *= 1.4 if opponent.hp * 2 < opponent.totalhp
    return miniscore
  end

  def roastcode
    return 1 if !@opponent.item.nil? && !pbIsBerry?(@opponent.item) && !pbIsTypeGem?(@opponent.item) || @opponent.ability == :STICKYHOLD || @opponent.effects[:Substitute] > 0

    miniscore = 1.0
    miniscore *= 1.2 if !@opponent.item.nil? && pbIsBerry?(@opponent.item) && @opponent.item != :OCCABERRY
    miniscore *= 1.3 if @opponent.item == :LUMBERRY || @opponent.item == :SITRUSBERRY || @opponent.item == :PETAYABERRY || @opponent.item == :LIECHIBERRY || @opponent.item == :SALACBERRY || @opponent.item == :CUSTAPBERRY
    miniscore *= 1.4 if !@opponent.item.nil? && pbIsTypeGem?(@opponent.item)
    return miniscore
  end

  def nomcode
    return 1 if @opponent.effects[:Substitute] > 0 || (!@opponent.item.nil? && !pbIsBerry?(@opponent.item))
    miniscore=1.0
    case @opponent.item
      when :LUMBERRY then miniscore*=2 if !@attacker.status.nil?
      when :CHERIBERRY then miniscore*=2 if @attacker.status == :PARALYSIS
      when :RAWSTBERRY then miniscore*=2 if @attacker.status == :BURN
      when :PECHABERRY then miniscore*=2 if @attacker.status == :POISON
      when :SITRUSBERRY, :FIGYBERRY, :WIKIBERRY, :MAGOBERRY, :AGUAVBERRY, :IAPAPABERRY then miniscore*=1.6 if @attacker.hp*(1.0/@attacker.totalhp)<0.66
      when :LIECHIBERRY then miniscore*=1.5 if @attacker.attack>@attacker.spatk
      when :PETAYABERRY then miniscore*=1.5 if @attacker.spatk>@attacker.attack
      when :CUSTAPBERRY, :SALACBERRY then miniscore*= pbAIfaster? ? 1.1 : 1.5
      else
        miniscore*=1.1
    end
    return miniscore
  end

  def teaslurpcode
    miniscore=1.0
    if !(@attacker.item.nil? || !pbIsBerry?(@attacker.item))
      case @attacker.item
        when :LUMBERRY then miniscore*=2 if !@attacker.status.nil?
        when :SITRUSBERRY, :FIGYBERRY, :WIKIBERRY, :MAGOBERRY, :AGUAVBERRY, :IAPAPABERRY then miniscore*=1.6 if @attacker.hp*(1.0/@attacker.totalhp)<0.66
        when :LIECHIBERRY then miniscore*=1.5 if @attacker.attack>@attacker.spatk
        when :PETAYABERRY then miniscore*=1.5 if @attacker.spatk>@attacker.attack
        when :CUSTAPBERRY, :SALACBERRY then miniscore*= pbAIfaster? ? 1.1 : 1.5
        else
          miniscore*=1.1
      end
    end
    return miniscore if @opponent.item.nil? || !pbIsBerry?(@opponent.item)
    case @opponent.item
      when :LUMBERRY then miniscore*=0.5 if !@opponent.status.nil?
      when :SITRUSBERRY, :FIGYBERRY, :WIKIBERRY, :MAGOBERRY, :AGUAVBERRY, :IAPAPABERRY then miniscore*=0.65 if @opponent.hp*(1.0/@opponent.totalhp)<0.66
      when :LIECHIBERRY then miniscore*=0.7 if @opponent.attack>@opponent.spatk
      when :PETAYABERRY then miniscore*=0.7 if @opponent.spatk>@opponent.attack
      when :CUSTAPBERRY, :SALACBERRY then miniscore*= !pbAIfaster? ? 0.9 : 0.5
      else
        miniscore*=0.9
    end
    return miniscore
  end

  def perishcode
    return 0 if @opponent.effects[:PerishSong]>0
    return 4 if @opponent.pbNonActivePokemonCount==0
    return 0 if @attacker.pbNonActivePokemonCount==0
    miniscore=1.0
    # Gen 9 Mod - Added Shed Tail and Flip Turn
    miniscore*=1.5 if @attacker.pbHasMove?(:UTURN) || @attacker.pbHasMove?(:VOLTSWITCH) || @attacker.pbHasMove?(:FLIPTURN) || @attacker.pbHasMove?(:PARTINGSHOT) || @attacker.pbHasMove?(:SHEDTAIL)
    miniscore*=3 if PBStuff::TRAPPINGABILITIESAI.include?(@attacker.ability) || (@attacker.ability == :MAGNETPULL && @opponent.hasType?(:STEEL))  || @opponent.effects[:MeanLook]>0
    miniscore*=1.2 if @mondata.partyroles.any? {|role| role.include?(:SWEEPER)}
    miniscore*=1.2 if @attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.isHealingMove?}
    miniscore*=1.2 if @attacker.moves.any? {|moveloop| moveloop!=nil && (PBStuff::PROTECTMOVE).include?(moveloop.move)} && !unseenFistCheck(@opponent) # Gen 9 Mod - Method that also checks Punching Glove
    miniscore*=1-0.05*statchangecounter(@attacker,1,7)
    miniscore*=1+0.05*statchangecounter(@opponent,1,7)
    miniscore*=0.5 if checkAImoves(PBStuff::PIVOTMOVE)
    # Gen 9 Mod - Discourage status moves when current opponent has Good as Gold
    miniscore*=0 if @opponent.ability == :GOODASGOLD && @move.category == :status && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))
    # Gen 9 Mod - Added Shed Tail and Flip Turn
    miniscore*=0.1 if (PBStuff::TRAPPINGABILITIESAI.include?(@attacker.ability) || (@attacker.ability == :MAGNETPULL && @opponent.hasType?(:STEEL))  || @attacker.effects[:MeanLook]>0) && !(@attacker.pbHasMove?(:UTURN) || @attacker.pbHasMove?(:VOLTSWITCH)|| @attacker.pbHasMove?(:FLIPTURN) || @attacker.pbHasMove?(:PARTINGSHOT)) || @attacker.pbHasMove?(:SHEDTAIL)
    miniscore*=1.5 if @mondata.partyroles.any? {|role| role.include?(:PIVOT)}
    return miniscore
    end

  def noLeechSeed(leechTarget)
    return true if leechTarget.effects[:LeechSeed] > -1
    return true if leechTarget.hasType?(:GRASS)
    return true if leechTarget.effects[:Substitute] > 0
    return true if leechTarget.ability == :LIQUIDOOZE
    return true if leechTarget.ability == :MAGICBOUNCE
    return true if leechTarget.effects[:MagicCoat]==true
    return true if leechTarget.hp == 0
    return false
  end

  def leechcode
    return 0 if noLeechSeed(@opponent)
    miniscore=1.0
    # Gen 9 Mod - Discourage status moves when current opponent has Good as Gold
    miniscore*=0 if @opponent.ability == :GOODASGOLD && @move.category == :status && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))
    miniscore*=1.2 if (@mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL) || @mondata.roles.include?(:TANK))
    miniscore*=1.3 if @attacker.effects[:Substitute]>0
    miniscore*=1.2 if hpGainPerTurn(@opponent)>1 || (@mondata.attitemworks && @attacker.item == :BIGROOT) || @attacker.crested == :SHIINOTIC
    miniscore*=1.2 if @opponent.status== :PARALYSIS || @opponent.status== :SLEEP
    miniscore*=1.2 if @opponent.effects[:Confusion]>0
    miniscore*=1.2 if @opponent.effects[:Attract]>=0
    miniscore*=1.1 if @opponent.status== :POISON || @opponent.status== :BURN
    miniscore*=0.2 if checkAImoves(([:RAPIDSPIN] | PBStuff::PIVOTMOVE))
    if @opponent.hp==@opponent.totalhp
      miniscore*=1.1
    else
      miniscore*=(@opponent.hp*(1.0/@opponent.totalhp))
    end
    miniscore*=0.8 if @opponent.hp*2<@opponent.totalhp
    miniscore*=0.2 if @opponent.hp*4<@opponent.totalhp
    miniscore*=1.2 if @attacker.moves.any? {|moveloop| moveloop!=nil && (PBStuff::PROTECTMOVE).include?(moveloop.move)} && !unseenFistCheck(@opponent) # Gen 9 Mod - Method that also checks Punching Glove
    miniscore*=1 + 0.05*statchangecounter(@opponent,1,7,1)
    return miniscore
  end

  def moveturnselectriccode(alltypes,damagemove)
    miniscore=1.0
    maxnormal= alltypes ? checkAIbestMove().type==:NORMAL : true
    if pbAIfaster?(@move)
      miniscore*=0.9
    elsif @attacker.ability == :MOTORDRIVE && maxnormal
      miniscore*=1.5
    end
    miniscore*=1.5 if (@attacker.ability == :LIGHTNINGROD || @attacker.ability == :VOLTABSORB) && @attacker.hp.to_f < 0.6*@attacker.totalhp && maxnormal
    miniscore*=1.1 if @attacker.hasType?(:GROUND)
    if @battle.doublebattle
      miniscore*=1.2 if [:MOTORDRIVE, :LIGHTNINGROD, :VOLTABSORB].include?(@attacker.pbPartner.ability)
      miniscore*=1.1 if @attacker.pbPartner.hasType?(:GROUND)
    end
    miniscore*=0.5 if !maxnormal
    return miniscore
  end

  def bidecode
    miniscore = @attacker.hp * (1.0 / @attacker.totalhp)
    miniscore *= 0.5 if hasgreatmoves()
    miniscore *= 1.2 if notOHKO?(@attacker, @opponent, true)
    miniscore *= 0.2 if checkAIdamage() * 2 > @attacker.hp
    miniscore *= 0.7 if @attacker.hp * 3 < @attacker.totalhp
    miniscore *= 1.1 if (@mondata.attitemworks && @attacker.item == :LEFTOVERS) || ((@mondata.attitemworks && @attacker.item == :BLACKSLUDGE) && @attacker.hasType?(:POISON))
    miniscore *= 1.3 if @mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL)
    miniscore *= 1.3 if !pbAIfaster?()
    miniscore *= 0.5 if checkAImovesAllOpponents(PBStuff::SETUPMOVE)

    if getAIMemory().any? { |moveloop| moveloop != nil && moveloop.basedamage == 0 }
      miniscore *= 0.8
    elsif getAIMemory().length == 4
      miniscore *= 1.3
    end
    return miniscore
  end

  def rolloutcode
    miniscore=1.0
    miniscore*=1.1 if @opponent.pbNonActivePokemonCount==0 || PBStuff::TRAPPINGABILITIESAI.include?(@attacker.ability) || (@attacker.ability == :MAGNETPULL && @opponent.hasType?(:STEEL)) || @opponent.effects[:MeanLook]>0
    miniscore*=0.75 if @attacker.hp*(1.0/@attacker.totalhp)<0.75
    miniscore*=1+0.05*@attacker.stages[PBStats::ACCURACY] if @attacker.stages[PBStats::ACCURACY]<0
    miniscore*=1+0.05*@attacker.stages[PBStats::ATTACK] if @attacker.stages[PBStats::ATTACK]<0
    miniscore*=1-0.05*@opponent.stages[PBStats::EVASION] if @opponent.stages[PBStats::EVASION]>0
    miniscore*=0.8 if (@mondata.oppitemworks && @opponent.item == :LAXINCENSE) || (@mondata.oppitemworks && @opponent.item == :BRIGHTPOWDER)
    miniscore*=0.8 if accuracyWeatherAbilityActive?(@opponent)
    miniscore*=0.5 if @attacker.status== :PARALYSIS
    miniscore*=0.5 if @attacker.effects[:Confusion]>0
    miniscore*=0.5 if @attacker.effects[:Attract]>=0
    miniscore*= 1 - (@opponent.pbNonActivePokemonCount*0.05) if @opponent.pbNonActivePokemonCount>1
    miniscore*=1.2 if @attacker.effects[:DefenseCurl]
    miniscore*=1.5 if checkAIdamage()*3<@attacker.hp && (getAIMemory().length > 0)
    miniscore+=4 if hasbadmoves(15)
    miniscore*=0.8 if checkAImoves(PBStuff::PROTECTMOVE) && !(@move.contactMove? && unseenFistCheck(@attacker)) # Gen 9 Mod - Method that also checks Punching Glove
    return miniscore
  end

  def outragecode(score)
    return 1.3 if @attacker.ability == :OWNTEMPO
    return 1.3 if @move.move == :RAGINGFURY && [:VOLCANIC,:VOLCANICTOP].include?(@battle.FE)
    miniscore=1.0
    miniscore*=0.85 if score<100
    miniscore*=1.3 if (@mondata.attitemworks && @attacker.item == :LUMBERRY) || (@mondata.attitemworks && @attacker.item == :PERSIMBERRY)
    miniscore*=1-0.05*@attacker.stages[PBStats::ATTACK] if @attacker.stages[PBStats::ATTACK]>0
    miniscore*=1-0.025*(@battle.pbPokemonCount(@battle.pbPartySingleOwner(@attacker.index))) if (@battle.pbPokemonCount(@battle.pbPartySingleOwner(@attacker.index))) > 2
    miniscore*=0.7 if checkAImoves(PBStuff::PROTECTMOVE) && !(@move.contactMove? && unseenFistCheck(@attacker)) # Gen 9 Mod - Method that also checks Punching Glove
    miniscore*=0.7 if checkAIhealing()
    return miniscore
    end

  def spectralthiefcode
    miniscore= 0.10*statchangecounter(@opponent,1,7)
    miniscore*=(-1) if @attacker.ability == :CONTRARY
    miniscore*=2 if @attacker.ability == :SIMPLE
    miniscore+=1
    miniscore*=1.2 if @opponent.effects[:Substitute]>0
    return miniscore
  end

  def stupidmovecode
    return 0 if pbAIfaster?()
    return 0 if @opponent.stages[PBStats::SPEED]==0 && @attacker.stages[PBStats::SPEED]==0
    miniscore = 1 + 0.1*@opponent.stages[PBStats::SPEED] - 0.1*@attacker.stages[PBStats::SPEED]
    miniscore*=0.8 if @battle.doublebattle
    return miniscore
  end

  def spotlightcode
    return 0 if !@battle.doublebattle || @opponent.index!=@attacker.pbPartner.index
    miniscore=1.0
    bestmove1 = checkAIbestMove(@attacker.pbOpposing1) #grab moves opposing mons are going to use
    bestmove2 = checkAIbestMove(@attacker.pbOpposing2)
    if @opponent.ability == :FLASHFIRE || battler.pbPartner.crested == :DRUDDIGON
      miniscore*=3 if bestmove1.pbType(@attacker.pbOpposing1) ==:FIRE || bestmove2.pbType(@attacker.pbOpposing2) ==:FIRE
    elsif @opponent.ability == :STORMDRAIN || @opponent.ability == :DRYSKIN || @opponent.ability == :WATERABSORB
      miniscore*=3 if bestmove1.pbType(@attacker.pbOpposing1) ==:WATER || bestmove2.pbType(@attacker.pbOpposing2) ==:WATER
    elsif @opponent.ability == :MOTORDRIVE || @opponent.ability == :LIGHTNINGROD || @opponent.ability == :VOLTABSORB
      miniscore*=3 if bestmove1.pbType(@attacker.pbOpposing1) ==:ELECTRIC ||bestmove2.pbType(@attacker.pbOpposing2) ==:ELECTRIC
    elsif @opponent.ability == :SAPSIPPER || battler.pbPartner.crested == :WHISCASH
      miniscore*=3 if bestmove1.pbType(@attacker.pbOpposing1) ==:GRASS || bestmove2.pbType(@attacker.pbOpposing2) ==:GRASS
    elsif battler.pbPartner.crested == :SKUNTANK || @opponent.ability == :EARTHEATER # Gen 9 Mod - Added Earth Eater
      miniscore*=3 if bestmove1.pbType(@attacker.pbOpposing1) ==:GRASS || bestmove2.pbType(@attacker.pbOpposing2) ==:GROUND
    end
    miniscore*=2 if (bestmove1.contactMove? || bestmove2.contactMove?) && checkAImoves([:KINGSSHIELD, :BANEFULBUNKER, :SPIKYSHIELD, :SILKTRAP, :BURNINGBULWARK]) # Gen 9 Mod - Added Silky Trap and Burning Bulwark
    miniscore*=2 if checkAImoves([:COUNTER, :METALBURST, :MIRRORCOAT])
    miniscore*=1.5 if !pbAIfaster?(nil,nil,@attacker,@attacker.pbOpposing1)
    miniscore*=1.5 if !pbAIfaster?(nil,nil,@attacker,@attacker.pbOpposing2)
    return miniscore
  end

  def doodlecode # Gen 9 Mod - Doodle Code
    return 0 if (PBStuff::ABILITYBLACKLIST).include?(@opponent.ability)
    return 0 if (PBStuff::FIXEDABILITIES).include?(@attacker.ability)
    return 0 if (PBStuff::FIXEDABILITIES).include?(@attacker.pbPartner.ability)
    return 0 if @opponent.ability == 0 || (@attacker.ability == @opponent.ability && @attacker.pbPartner.ability == @opponent.ability)
    return 0 if ((@mondata.attitemworks && @attacker.item == :ABILITYSHIELD) || (@attacker.pbPartner.itemWorks? && @attacker.pbPartner.item == :ABILITYSHIELD))
    miniscore = getAbilityDisruptScore(@opponent,@attacker)
    miniminiPartner = getAbilityDisruptScore(@attacker.pbPartner,@opponent)
    minimini = getAbilityDisruptScore(@attacker,@opponent)
    return (1 + ((minimini+miniminiPartner)-miniscore))
  end

  def doubleshockcode # Double Shock
    return 0 if !@attacker.hasType?(:ELECTRIC)
    miniscore= (1-@opponent.pbNonActivePokemonCount*0.05)
    if @initial_scores[@score_index]<100
      miniscore*=0.9
      miniscore*=0.5 if getAIMemory().any? {|moveloop| moveloop!=nil && moveloop.isHealingMove?}
    end
    miniscore*=0.5 if @initial_scores.length>0 && hasgreatmoves()
    miniscore*=0.7 if @attacker.pbNonActivePokemonCount==0 && @opponent.pbNonActivePokemonCount!=0
    effcheck = PBTypes.twoTypeEff(@opponent.type1,(:ELECTRIC),(:ELECTRIC))
    miniscore*=1.5 if effcheck > 4
    miniscore*=0.5 if effcheck < 4
      effcheck = PBTypes.twoTypeEff(@opponent.type2,(:ELECTRIC),(:ELECTRIC))
    miniscore*=1.5 if effcheck > 4
    miniscore*=0.5 if effcheck < 4
    effcheck = PBTypes.twoTypeEff(checkAIbestMove().pbType(@opponent),(:ELECTRIC),(:ELECTRIC))
    miniscore*=1.5 if effcheck > 4
    miniscore*=0.5 if effcheck < 4
    return miniscore
  end

  def saltcurecode # Salt Cure
    return 1 if (@opponent.effects[:SaltCure] || secondaryEffectNegated?())
      miniscore=1.3
      miniscore*=3 if @opponent.hasType?(:WATER) || @opponent.hasType?(:STEEL)
    return miniscore
  end

  def shedtailcode # Gen 9 Mod - Shed Tail - Combined version of pivotcode and subcode specific for shed tail.
    return 0 if @attacker.hp*2<=@attacker.totalhp
    return 0 if @attacker.effects[:Substitute]>0 && pbAIfaster?(@move)
    return 0 if @attacker.pbNonActivePokemonCount==1 && $game_switches[:Last_Ace_Switch]
    return @move.basedamage > 0 ? 1 : 0 if @attacker.pbNonActivePokemonCount==0 || @battle.FE == :COLOSSEUM

    miniscore = 1.0
    miniscore*= (@attacker.hp==@attacker.totalhp) ? 1.1 : (@attacker.hp*(1.0/@attacker.totalhp))
    miniscore*=1.2 if @opponent.effects[:LeechSeed]>=0
    miniscore*=1.2 if checkAImoves([:SPORE, :SLEEPPOWDER])
    miniscore*=1.5 if @opponent.status== :SLEEP
    miniscore*=0.3 if @opponent.ability == :INFILTRATOR
    miniscore*=0.3 if checkAImoves([:UPROAR, :HYPERVOICE, :ECHOEDVOICE, :SNARL, :BUGBUZZ, :BOOMBURST, :SPARKLINGARIA, :CLANGINGSCALES, :OVERDRIVE, :TORCHSONG, :PSYCHICNOISE])
    miniscore*=2   if checkAIdamage()*4 < @attacker.totalhp && (getAIMemory().length > 0)
    miniscore*=1.3 if @opponent.effects[:Confusion]>0
    miniscore*=1.3 if @opponent.status== :PARALYSIS
    miniscore*=1.3 if @opponent.effects[:Attract]>=0
    miniscore*=0.5 if @battle.doublebattle

    miniscore=1.0
    miniscore*=0.7 if @attacker.pbOwnSide.effects[:StealthRock]
    miniscore*=0.6 if @attacker.pbOwnSide.effects[:StickyWeb]
    miniscore*=0.9**@attacker.pbOwnSide.effects[:Spikes] if @attacker.pbOwnSide.effects[:Spikes]>0
    miniscore*=0.9**@attacker.pbOwnSide.effects[:ToxicSpikes] if @attacker.pbOwnSide.effects[:ToxicSpikes]>0
    miniscore*=1.1 if @opponent.ability == :INTIMIDATE

    miniscore*=1.1 if @attacker.ability == :SUPERSWEETSYRUP
    if @opponent.ability == :PRESSURE || @opponent.ability == :UNNERVE
      if @battle.FE == :DIMENSIONAL || @battle.FE == :FROZENDIMENSIONAL
        miniscore *= 1.2
      else
        miniscore *= 1.1
      end
    end
    miniscore*=1.1 if @battle.FE == :CITY && @opponent.ability == :FRISK
    miniscore*=1.1 if @opponent.crested == :THIEVUL

    if @attacker.ability == :REGENERATOR
      miniscore*=1.5
    end
    miniscore*=1.8 if @mondata.partyroles.any? {|role| role.include?(:SWEEPER)}

    movebackup = @move ; attackerbackup = @attacker ; oppbackup = @opponent
    miniscore*=0.2 if getSwitchInScoresParty(pbAIfaster?(@move)).max < 50
    @move = movebackup ; @attacker = attackerbackup ; @opponent = oppbackup

    miniscore*= 1-0.15*statchangecounter(@attacker,1,7,-1)
    miniscore*=1-0.25*statchangecounter(@attacker,1,7,1)
    miniscore*=1.1 if @mondata.roles.include?(:LEAD)
    miniscore*=1.1 if @mondata.roles.include?(:PIVOT)
    miniscore*=1.2 if pbAIfaster?(@move)
    miniscore*=1.3 if @attacker.effects[:Toxic]>0 || @attacker.effects[:Attract]>-1 || @attacker.effects[:Confusion]>0 || @attacker.effects[:Yawn]>0
    # Gen 9 Mod - Additinoal Checks for Salt Cure
    miniscore*=1.2 if @attacker.effects[:SaltCure] && @attacker.ability != :MAGICGUARD
    miniscore*=1.3 if @attacker.effects[:SaltCure] && @attacker.ability != :MAGICGUARD && (@attacker.hasType?(:WATER) || @attacker.hasType?(:STEEL))
    miniscore*=1.5 if @attacker.effects[:LeechSeed]>-1
    miniscore*=1.5 if @attacker.effects[:PerishSong]>0 || @attacker.effects[:Curse]

    miniscore*=0.5 if hasgreatmoves()
    if hasbadmoves(25)
      miniscore*=2
    elsif hasbadmoves(40)
      miniscore*=1.2
    end
    return miniscore
  end

  def tidyupcode # Tidy Up - Modified version of defogcode that doesn't deal with screens.
    miniscore = 1.0
    yourpartycount = @battle.pbPokemonCount(@battle.pbPartySingleOwner(@attacker.index))
    theirpartycount = @battle.pbPokemonCount(@battle.pbPartySingleOwner(@opponent.index))
    if yourpartycount>1
      miniscore*=2 if @attacker.pbOwnSide.effects[:StealthRock]
      miniscore*=3 if @attacker.pbOwnSide.effects[:StickyWeb]
      miniscore*=(1.5**@attacker.pbOwnSide.effects[:Spikes])
      miniscore*=(1.7**@attacker.pbOwnSide.effects[:ToxicSpikes])
    end
    miniscore -= 1.0
    miniscore*=(yourpartycount-1) if yourpartycount>1
    minimini = 1.0
    if theirpartycount>1
      minimini*=0.5 if @opponent.pbOwnSide.effects[:StealthRock]
      minimini*=0.3 if @opponent.pbOwnSide.effects[:StickyWeb]
      minimini*=(0.7**@opponent.pbOwnSide.effects[:Spikes])
      minimini*=(0.6**@opponent.pbOwnSide.effects[:ToxicSpikes])
    end
    minimini -= 1.0
    minimini*=(theirpartycount-1) if theirpartycount>1
    miniscore+=minimini
    miniscore+=1.0
    miniscore*= 0.8 if @attacker.effects[:Substitute]>0
    miniscore *= 1.25 if @opponent.effects[:Substitute]>0
    if miniscore<0
      miniscore=0
    end
    return miniscore
  end

  def dragoncheercode # Dragon Cheer - Modified version of focusenergycode that is affected by us having a
                      # Dragon type ally, and checks for effects on our ally instead of us.
    partnerDragon = @attacker.pbPartner.hasType?(:DRAGON)
    return 0 if @attacker.pbPartner.hp==0 || !@battle.doublebattle
    return 0 if @attacker.pbPartner.effects[:FocusEnergy]>0
    miniscore = 1.0
    miniscore*=4.0 if partnerDragon
    partnerHPpercent = (@attacker.pbPartner.hp.to_f)/@attacker.pbPartner.totalhp
    if partnerHPpercent>0.75
      miniscore*=1.2
    elsif partnerHPpercent > 0.5 && partnerHPpercent < 0.75 && (@attacker.pbPartner.ability == :EMERGENCYEXIT || @attacker.pbPartner.ability == :WIMPOUT || (@attacker.pbPartner.itemWorks? && @attacker.pbPartner.item == :EJECTBUTTON))
      miniscore*=0.3
    elsif partnerHPpercent < 0.33
      miniscore*=0.3
    end
    miniscore*=1.3 if @opponent.effects[:HyperBeam]>0
    miniscore*=1.7 if @opponent.effects[:Yawn]>0
    miniscore*=0.6 if @attacker.pbPartner.effects[:LeechSeed]>=0 || @attacker.pbPartner.effects[:Attract]>=0
    miniscore*=0.5 if checkAImoves(PBStuff::PHASEMOVE)
    miniscore*=0.2 if @attacker.pbPartner.effects[:Confusion]>0
    miniscore*=0.3 if @attacker.pbPartner.pbOpposingSide.effects[:Retaliate]
    miniscore*=1.2 if (@attacker.pbPartner.hp/4.0)>checkAIdamage()
    miniscore*=1.2 if !@opponent.status.nil?
    miniscore*=1.3 if @opponent.status== :SLEEP || (@opponent.status== :FROZEN && !KAIZOMOD)
    miniscore*=1.5 if @opponent.effects[:Encore]>0 && @opponent.moves[(@opponent.effects[:EncoreIndex])].basedamage==0
    miniscore*=2 if @attacker.pbPartner.ability == :SUPERLUCK || @attacker.pbPartner.ability == :SNIPER
    miniscore*=1.2 if @mondata.attitemworks && (@attacker.pbPartner.item == :SCOPELENS || @attacker.pbPartner.item == :RAZORCLAW || (@attacker.pbPartner.item == :STICK && @attacker.pbPartner.pokemon.species==:FARFETCHD) || (@attacker.pbPartner.item == :LUCKYPUNCH && @attacker.pbPartner.pokemon.species==:CHANSEY))
    miniscore*=1.3 if (@mondata.attitemworks && @attacker.pbPartner.item == :LANSATBERRY)
    miniscore*=0.2 if @opponent.ability == :ANGERPOINT || @opponent.ability == :SHELLARMOR || @opponent.ability == :BATTLEARMOR
    miniscore*=0.5 if @attacker.pbPartner.pbHasMove?(:LASERFOCUS) || @attacker.pbPartner.pbHasMove?(:FROSTBREATH) || @attacker.pbPartner.pbHasMove?(:STORMTHROW)
    miniscore*= 2**(@attacker.pbPartner.moves.count{|moveloop| moveloop!=nil && moveloop.highCritRate?})
    return miniscore
  end

######################################################
# Utility functions
######################################################

  def pbGetMonRoles(targetmon=nil)
    partyRoles = []
    party = targetmon ? [targetmon] : @mondata.party
    for mon in party
      monRoles=[]
      movelist = []
      if targetmon && targetmon.class==PokeBattle_Pokemon || !targetmon
        for i in mon.moves
          next if i.nil?
          movelist.push(i.move)
        end
      elsif targetmon && targetmon.class==PokeBattle_Battler
        for i in targetmon.moves
          next if i.nil?
          movelist.push(i.move)
        end
      end
      monRoles.push(:LEAD) if @mondata.party.index(mon)==0 || (@mondata.party.index(mon)==1 && @battle.doublebattle && @battle.pbParty(@mondata.index)==@battle.pbPartySingleOwner(@mondata.index))
      monRoles.push(:ACE) if @mondata.party.index(mon)==(@mondata.party.length-1)
      secondhighest=true
      if party.length>2
        for i in 0..(party.length-2)
          next if party[i].nil?
          secondhighest=false if mon.level<party[i].level
        end
      end
      for i in movelist
        next if i.nil?
        healingmove=true if $cache.moves[i] && $cache.moves[i].checkFlag?(:healingmove)
        curemove=true if (i == :HEALBELL || i == :AROMATHERAPY)
        wishmove=true if i == :WISH
        phasemove=true if PBStuff::PHASEMOVE.include?(i)
        pivotmove=true if PBStuff::PIVOTMOVE.include?(i)
        spinmove=true if i == :RAPIDSPIN
        batonmove=true if i == :BATONPASS
        screenmove=true if PBStuff::SCREENMOVE.include?(i)
        tauntmove=true if i == :TAUNT
        restmove=true if i == :REST
        weathermove = true if [:SUNNYDAY, :RAINDANCE, :HAIL, :SANDSTORM, :SHADOWSKY, :CHILLYRECEPTION].include?(i)
        fieldmove=true if (i == :GRASSYTERRAIN || i == :ELECTRICTERRAIN || i == :MISTYTERRAIN || i == :PSYCHICTERRAIN || i == :MIST || i == :IONDELUGE || i == :TOPSYTURVY)
      end
      monRoles.push(:SWEEPER)     if mon.ev[3]>251 && (mon.nature==:MODEST || mon.nature==:JOLLY || mon.nature==:TIMID || mon.nature==:ADAMANT) || (mon.item==(:CHOICEBAND) || mon.item==(:CHOICESPECS) || mon.item==(:CHOICESCARF) || mon.ability == :GORILLATACTICS)
      monRoles.push(:PHYSICALWALL) if healingmove && (mon.ev[2]>251 && (mon.nature==:BOLD || mon.nature==:RELAXED || mon.nature==:IMPISH || mon.nature==:LAX))
      monRoles.push(:SPECIALWALL)  if healingmove && (mon.ev[5]>251 && (mon.nature==:CALM || mon.nature==:GENTLE || mon.nature==:SASSY || mon.nature==:CAREFUL))
      monRoles.push(:CLERIC)     if curemove || (wishmove && mon.ev[0]>251)
      monRoles.push(:PHAZER)     if phasemove
      monRoles.push(:SCREENER)   if mon.item==(:LIGHTCLAY) && screenmove
      # Gen 9 Mod - Added Hospitality
      monRoles.push(:PIVOT)     if (pivotmove && healingmove) || (mon.ability == :REGENERATOR) || (mon.ability == :HOSPITALITY)
      monRoles.push(:SPINNER)     if spinmove
      monRoles.push(:TANK)     if (mon.ev[0]>251 && !healingmove) || mon.item==(:ASSAULTVEST)
      monRoles.push(:BATONPASSER)   if batonmove
      monRoles.push(:STALLBREAKER) if tauntmove || mon.item==(:CHOICEBAND) || mon.item==(:CHOICESPECS) || mon.ability == :GORILLATACTICS
      monRoles.push(:STATUSABSORBER) if restmove || (mon.ability == :COMATOSE) || mon.item==(:TOXICORB) || mon.item==(:FLAMEORB) || (mon.ability == :GUTS) || (mon.ability == :QUICKFEET)|| (mon.ability == :FLAREBOOST) || (mon.ability == :TOXICBOOST) || (mon.ability == :NATURALCURE) || (mon.ability == :MAGICGUARD) || (mon.ability == :MAGICBOUNCE) || (mon.species == :ZANGOOSE && mon.item == :ZANGCREST) || hydrationCheck(mon) || (mon.ability == :GOODASGOLD) # Gen 9 Mod - Added Good as Gold
      monRoles.push(:TRAPPER)     if PBStuff::TRAPPINGABILITIES.include?(mon.ability)
      # Gen 9 Mod - Added Orichalcum Pulse
      monRoles.push(:WEATHERSETTER) if weathermove || (mon.ability == :DROUGHT) || (mon.ability == :SANDSPIT)  || (mon.ability == :SANDSTREAM) || (mon.ability == :DRIZZLE) || (mon.ability == :SNOWWARNING) || (mon.ability == :PRIMORDIALSEA) || (mon.ability == :DESOLATELAND) || (mon.ability == :DELTASTREAM) || (mon.ability == :ORICHALCUMPULSE)
      # Gen 9 Mod - Added Seed Sower & Hadron Engine
      monRoles.push(:FIELDSETTER)   if fieldmove || (mon.ability == :GRASSYSURGE) || (mon.ability == :ELECTRICSURGE) || (mon.ability == :MISTYSURGE) || (mon.ability == :PSYCHICSURGE) || mon.item==(:AMPLIFIELDROCK)|| (mon.ability == :DARKSURGE) || (mon.ability == :SEEDSOWER) || (mon.ability == :HADRONENGINE)
      monRoles.push(:SECOND)     if secondhighest
      partyRoles.push(monRoles)
    end
    return partyRoles[0] if targetmon
    return partyRoles
  end

  def pbMakeFakeBattler(pokemon, partyindex, batonpass = false, index = @index)
    return nil if pokemon.nil?

    pokemon = pokemon.clone
    battler = PokeBattle_Battler.new(@battle, index, true)
    battler.pbInitPokemon(pokemon, partyindex)
    battler.pbInitEffects(batonpass, true)
    return battler
  end

  def pbSereneGraceCheck(miniscore)
    miniscore-=1
    if @move.effect != 100
      addedeffect = @move.effect.to_f
      if (KAIZOMOD)
        addedeffect = 30 if @move.move == :FREEZINGGLARE
        addedeffect = 20 if @move.move == :BLIZZARD
        addedeffect = 20 if @move.move == :FREEZEDRY
      end
      addedeffect*=2 if @attacker.ability == :SERENEGRACE || @battle.FE == :RAINBOW
      addedeffect=100 if addedeffect>100
      miniscore*=addedeffect/100.0
    end
    miniscore+=1
    return miniscore
  end

  def pbReduceWhenKills(miniscore)
    return miniscore if @initial_scores[@score_index] < 100
    return Math.sqrt(miniscore)
  end

  def statchangecounter(mon,initial,final,limiter=0)
    count = 0
    case limiter
      when 0 #all stats
      for i in initial..final
        count += mon.stages[i]
      end
      when 1 #increases only
      for i in initial..final
        count += mon.stages[i] if mon.stages[i]>0
      end
      when -1 #decreases only
      for i in initial..final
        count += mon.stages[i] if mon.stages[i]<0
      end
    end
    return count
  end

  def hasgreatmoves()
    #slight variance in precision based on trainer skill
    threshold = 100
    #threshold = 105 if @mondata.skill>=HIGHSKILL
    #threshold = 110 if @mondata.skill>=BESTSKILL
    for i in 0...@initial_scores.length
      next if i == @score_index
      if @initial_scores[i]>=threshold
        return true
      end
    end
    return false
  end

  def hasbadmoves(threshold,initialscores=@initial_scores,scoreindex=@score_index)
    for i in 0...initialscores.length
      next if i==scoreindex
      return false if initialscores[i]>threshold
    end
    return true
  end

  def getStatusDamage(move=@move)
    return 20 if move.zmove && (move.move == :CONVERSION || move.move == :SPLASH || move.move == :CELEBRATE)
    return PBStuff::STATUSDAMAGE[move.move] if PBStuff::STATUSDAMAGE[move.move]
    return 0
  end

  def pbRoughStat(battler, stat)
    return battler.pbSpeed if @mondata.skill >= HIGHSKILL && stat == PBStats::SPEED

    stage = battler.stages[stat] + 6
    value = 0
    value = battler.attack if stat == PBStats::ATTACK
    value = battler.defense if stat == PBStats::DEFENSE
    value = battler.speed if stat == PBStats::SPEED
    value = battler.spatk if stat == PBStats::SPATK
    value = battler.spdef if stat == PBStats::SPDEF
    return (value * PBStats::StageMul[stage]).floor
  end

  def pbRoughAccuracy(move,attacker,opponent)
    # start with stuff that has set accuracy
    # Override accuracy
    return 100 if attacker.ability == :NOGUARD || opponent.ability == :NOGUARD || (attacker.ability == :FAIRYAURA && @battle.FE == :FAIRYTALE) && @mondata.skill>=MEDIUMSKILL
    return 100 if move.accuracy==0   # Doesn't do accuracy check (always hits)
    if @mondata.skill>=BESTSKILL
      baseaccuracy=move.accuracy
      fieldmove = @battle.field.moveData(move.move)
      baseaccuracy = fieldmove[:accmod] if fieldmove && fieldmove[:accmod]
      return 100 if baseaccuracy == 0 # Doesn't do accuracy check (always hits)
    end
    return 100 if move.function==0xA5 # Swift
    if @mondata.skill>=MEDIUMSKILL
      return 100 if opponent.effects[:LockOn]>0 && opponent.effects[:LockOnPos]==attacker.index
      if move.function==0x70 # OHKO moves
        return 0 if opponent.ability == :STURDY || opponent.level>attacker.level || (@battle.FE == :CHESS && opponent.pokemon.piece==:PAWN) || (@battle.FE == :COLOSSEUM && opponent.ability == :STALWART)
        return move.accuracy+attacker.level-opponent.level
      end
      return 100 if opponent.effects[:Telekinesis]>0
      return 100 if move.function==0x0D && @battle.pbWeather == :HAIL # Blizzard
      return 100 if (move.function==0x08 || move.function==0x15) && @battle.pbWeather == :RAINDANCE# Thunder, Hurricane
      return 100 if move.function==0x08 && (@battle.FE == :MOUNTAIN || @battle.FE == :SNOWYMOUNTAIN) # Thunder
      return 100 if move.type == :ELECTRIC && @battle.FE == :UNDERWATER
      return 100 if attacker.hasType?(:POISON) && move.move == :TOXIC
      if @mondata.skill>=HIGHSKILL
        return 100 if (move.function==0x10 || move.move == :BODYSLAM || move.function==0x137 || move.function==0x9B || move.function==0x806) && opponent.effects[:Minimize] # Flying Press, Stomp, DRush, Mal. Moonsault
        return 100 if @battle.FE == :MIRROR && (PBFields::BLINDINGMOVES + [:MIRRORSHOT]).include?(move.move)
        return 100 if @battle.FE == :MIRROR && move.basedamage>0 && move.target==:SingleNonUser && !move.contactMove? && move.pbIsSpecial?(move.type) && opponent.stages[PBStats::EVASION]>0
      end
    end
    # Get base accuracy
    baseaccuracy=move.accuracy

    if @mondata.skill>=BESTSKILL
      fieldmove = @battle.field.moveData(move.move)
      baseaccuracy = fieldmove[:accmod] if fieldmove && fieldmove[:accmod]
    end
    if @mondata.skill>=MEDIUMSKILL
      baseaccuracy=50 if @battle.pbWeather== :SUNNYDAY && (move.function==0x08 || move.function==0x15) # Thunder, Hurricane
      end
    # Accuracy stages
    accstage=attacker.stages[PBStats::ACCURACY]
    accstage=0 if opponent.ability == :UNAWARE && !(moldBreakerCheck(attacker) || myceliumMightCheck(attacker, move)) # Gen 9 Mod - Added myceliumMightCheck
    accuracy=(accstage>=0) ? (accstage+3)*100.0/3 : 300.0/(3-accstage)
    evastage=opponent.stages[PBStats::EVASION]
    evastage-=2 if @battle.state.effects[:Gravity]!=0
    evastage=-6 if evastage<-6
    evastage=0 if opponent.effects[:Foresight] || opponent.effects[:MiracleEye] || move.function==0xA9 || attacker.ability == :UNAWARE && !(moldBreakerCheck(opponent) || myceliumMightCheck(opponent, move)) # Gen 9 Mod - Added myceliumMightCheck
    evasion=(evastage>=0) ? (evastage+3)*100.0/3 : 300.0/(3-evastage)
    # Accuracy modifiers
    if @mondata.skill>=MEDIUMSKILL
      accuracy*=1.3 if attacker.ability == :COMPOUNDEYES
      accuracy*=1.1 if attacker.ability == :VICTORYSTAR
      if @mondata.skill>=HIGHSKILL
        accuracy*=1.1 if attacker.pbPartner.ability == :VICTORYSTAR
        accuracy*= [:BACKALLEY,:CITY].include?(@battle.FE) ? 0.67 : 0.8 if attacker.ability == :HUSTLE && move.basedamage>0 && move.pbIsPhysical?(move.pbType(attacker)) && !moldBreakerCheck(opponent)
      end
      if @mondata.skill>=BESTSKILL
        accuracy*=0.9 if attacker.ability == :LONGREACH && (@battle.FE == :ROCKY || @battle.FE == :FOREST) # Rocky Field # Forest Field
        accuracy*= @battle.FE == :RAINBOW ? 0 : 0.5 if opponent.ability == :WONDERSKIN && @basedamage==0 && attacker.pbIsOpposing?(opponent.index) && !(moldBreakerCheck(attacker) || myceliumMightCheck(attacker, move)) # Gen 9 Mod - Added myceliumMightCheck
        accuracy*=0.5 if Rejuv && @battle.FE == :PSYTERRAIN && opponent.ability == :MAGICIAN && @basedamage==0 && attacker.pbIsOpposing?(opponent.index) && !(moldBreakerCheck(attacker) || myceliumMightCheck(attacker, move)) # Gen 9 Mod - Added myceliumMightCheck
        evasion*=1.2 if opponent.ability == :TANGLEDFEET && opponent.effects[:Confusion]>0 && !(moldBreakerCheck(attacker) || myceliumMightCheck(attacker, move)) # Gen 9 Mod - Added myceliumMightCheck
        evasion*=1.2 if (@battle.pbWeather== :SANDSTORM || @battle.FE == :DESERT || @battle.FE == :ASHENBEACH) && opponent.ability == :SANDVEIL && !(moldBreakerCheck(attacker) || myceliumMightCheck(attacker, move)) # Gen 9 Mod - Added myceliumMightCheck
        evasion*=1.2 if (@battle.pbWeather== :HAIL || @battle.FE == :ICY || @battle.FE == :SNOWYMOUNTAIN) && opponent.ability == :SNOWCLOAK && !(moldBreakerCheck(attacker) || myceliumMightCheck(attacker, move)) # Gen 9 Mod - Added myceliumMightCheck
      end
      if attacker.itemWorks?
        accuracy*=1.1 if attacker.item == :WIDELENS
        accuracy*=1.2 if attacker.item == :ZOOMLENS && attacker.pbSpeed<opponent.pbSpeed
        if attacker.item == :MICLEBERRY
          accuracy*=1.2 if (attacker.ability == :GLUTTONY && attacker.hp<=(attacker.totalhp/2.0).floor) || attacker.hp<=(attacker.totalhp/4.0).floor
        end
        if @mondata.skill>=HIGHSKILL
          evasion*=1.1 if opponent.item == :BRIGHTPOWDER
          evasion*=1.1 if opponent.item == :LAXINCENSE
        end
      end
    end
    evasion = 100 if attacker.ability == :KEENEYE || attacker.ability == :MINDSEYE # Gen 9 Mod - Added Mind's Eye
    evasion = 100 if @mondata.skill >= BESTSKILL && @battle.FE == :ASHENBEACH && [:OWNTEMPO, :INNERFOCUS, :PUREPOWER, :SANDVEIL, :STEADFAST].include?(attacker.ability) && ![:UNNERVE, :ASONECHILLING, :ASONEGRIM].include?(opponent.ability)
    accuracy *= baseaccuracy / evasion.to_f
    accuracy = 100 if accuracy > 100
    return accuracy
  end

  def pbAIfaster?(attackermove = nil, opponentmove = nil, attacker = @attacker, opponent = @opponent)
    return true if !opponent || opponent.hp == 0
    return false if !attacker || attacker.hp == 0

    return (pbRoughStat(opponent, PBStats::SPEED) < attacker.pbSpeed) ^ (@battle.trickroom != 0) if @mondata.skill < HIGHSKILL

    priorityarray = [[0, 0, 0, attacker], [0, 0, 0, opponent]]
    index = -1
    for battler in [attacker, opponent]
      index += 1
      battlermove = (battler == attacker) ? attackermove : opponentmove
      priorityarray[index][1] = -1 if battler.ability == :STALL
      priorityarray[index][1] = 1 if battler.hasWorkingItem(:CUSTAPBERRY) && ((battler.ability == :GLUTTONY && battler.hp <= (battler.totalhp / 2.0).floor) || battler.hp <= (battler.totalhp / 4.0).floor)
      priorityarray[index][1] = -2 if (battler.itemWorks? && (battler.item == :LAGGINGTAIL || battler.item == :FULLINCENSE))
      # speed priority
      priorityarray[index][2] = battler.pbSpeed if @battle.trickroom == 0
      priorityarray[index][2] = -battler.pbSpeed if @battle.trickroom > 0
      next if !battlermove

      pri = 0
      pri = battlermove.priority if !battlermove.zmove
      pri = pri.nil? ? 0 : pri
      pri += 1 if battler.ability == :PRANKSTER && battlermove.basedamage == 0 # Is status move
      pri += 1 if battler.ability == :GALEWINGS && battlermove.type == :FLYING && (battler.hp >= battler.totalhp / 2 || @battle.FE == :SKY || ((@battle.FE == :MOUNTAIN || @battle.FE == :SNOWYMOUNTAIN || @battle.FE == :VOLCANICTOP) && @battle.pbWeather == :STRONGWINDS))
      pri += 1 if @battle.FE == :CHESS && battler.pokemon && battler.pokemon.piece == :KING
      pri += 1 if battlermove.move == :GRASSYGLIDE && (@battle.FE == :GRASSY || @battle.state.effects[:GRASSY] > 0 || @battle.FE == :SWAMP)
      pri += 1 if battlermove.move == :ATTACKORDER && battler.crested == :VESPIQUEN
      pri += 3 if battler.ability == :TRIAGE && PBStuff::HEALFUNCTIONS.include?(battlermove.function)
      pri -= 1 if @battle.FE == :DEEPEARTH && battlermove.move == :COREENFORCER
      pri -= 2 if battler.ability == :MYCELIUMMIGHT && battlermove.basedamage == 0 && battler.effects[:TwoTurnAttack] == 0 # is Status Move # Gen 9 Mod - Added Mycelium Might
      # pri = -6 if battler.species == :CORVIKNIGHT && battler.giga && battlermove.move == :BRAVEBIRD

      priorityarray[index][0] = pri
    end
    priorityarray.sort_by! { |a| [a[0], a[1], a[2]] }
    priorityarray.reverse!
    return false if priorityarray[0][0] == priorityarray[1][0] && priorityarray[0][1] == priorityarray[1][1] && priorityarray[0][2] == priorityarray[1][2]

    return priorityarray[0][3] == attacker
  end

  def pbMoveOrderAI #lol it's just pbPriority
    priorityarray = []
    for i in 0..3
      battler = @battle.battlers[i]
      priorityarray[i] =[0,0,0,i]
      if battler.hp == 0
        priorityarray[i] =[-1,0,0,i]
        next
      end
      priorityarray[i][0] = 1 if battler.pokemon && battler.pokemon.piece == :KING && @battle.FE == :CHESS
      priorityarray[i][1] = -1 if battler.ability == :STALL
      priorityarray[i][1] = 1 if battler.hasWorkingItem(:CUSTAPBERRY) && ((battler.ability == :GLUTTONY && battler.hp<=(battler.totalhp/2.0).floor) || battler.hp<=(battler.totalhp/4.0).floor)
      priorityarray[i][1] = -2 if (battler.itemWorks? && (battler.item == :LAGGINGTAIL || battler.item == :FULLINCENSE))
      #speed priority
      priorityarray[i][2] = pbRoughStat(battler,PBStats::SPEED) if @battle.trickroom==0
      priorityarray[i][2] = -pbRoughStat(battler,PBStats::SPEED) if @battle.trickroom>0
    end
    priorityarray.sort!
    priorityarray.reverse!
    moveorderarray = []
    for i in 0..3
      moveorderarray[i] = priorityarray[i][3]
    end
    return moveorderarray
  end

  def hpGainPerTurn(attacker=@attacker)
    healing = 1
    # Negative healing effects
    if attacker.ability != :MAGICGUARD && !(attacker.ability == :WONDERGUARD && @battle.FE == :COLOSSEUM)
      if (@battle.FE == :BURNING || @battle.FE == :VOLCANIC) && !attacker.isAirborne? && attacker.burningFieldPassiveDamage?
        subscore = 0
        subscore += PBTypes.twoTypeEff(:FIRE,attacker.type1,attacker.type2)/32.0
        subscore*=2.0 if (attacker.ability == :LEAFGUARD) || (attacker.ability == :ICEBODY) || (attacker.ability == :FLUFFY) || (attacker.ability == :GRASSPELT)
        subscore*=2.0 if attacker.effects[:TarShot]
        healing -= subscore
      end
      if @battle.FE == :UNDERWATER && attacker.underwaterFieldPassiveDamamge?
        subscore = 0
        subscore += PBTypes.twoTypeEff(:WATER,attacker.type1,attacker.type2)/32.0
        subscore*=2.0 if (attacker.ability == :FLAMEBODY) || (attacker.ability == :MAGMAARMOR)
        healing -= subscore
      end
      if @battle.FE == :MURKWATERSURFACE && attacker.murkyWaterSurfacePassiveDamage?
        subscore = 0
        subscore += PBTypes.twoTypeEff(:POISON,attacker.type1,attacker.type2)/32.0
        subscore*=2.0 if (attacker.ability == :FLAMEBODY) || (attacker.ability == :MAGMAARMOR) || attacker.ability == :DRYSKIN || attacker.ability == :WATERABSORB
        healing -= subscore
      end
      # Field effect induced
      healing -= 0.125 if @battle.FE == :CORROSIVE && (attacker.ability == :GRASSPELT || attacker.ability == :DRYSKIN)
      healing -= 0.125 if @battle.FE == :DESERT &&  attacker.ability == :DRYSKIN
      healing -= 0.125 if @battle.FE == :CORRUPTED &&  attacker.ability == :DRYSKIN && !attacker.hastype?(:POISON)
      healing -= 0.125 if Rejuv && @battle.FE == :DESERT && @battle.pbWeather == :SUNNYDAY && (attacker.hasType?(:GRASS) || attacker.hasType?(:WATER))
      healing -= 0.0625 if attacker.effects[:AquaRing] && @battle.FE == :CORROSIVEMIST && !attacker.hasType?(:STEEL) && !attacker.hasType?(:POISON) || !@battle.pbCheckGlobalAbility(:NEUTRALIZINGGAS)
      healing -= 0.0625 if attacker.effects[:Ingrain] && (@battle.FE == :SWAMP || @battle.FE == :CORROSIVE || @battle.FE == :CORRUPTED) && !(attacker.hasType?(:STEEL) || attacker.hasType?(:POISON))
      healing -= 0.0625 if @battle.FE == :HAUNTED && attacker.status == :SLEEP && !attacker.hasType?(:GHOST)
      healing -= 0.0625 if (@battle.FE == :DIMENSIONAL && attacker.effects[:HealBlock])
      healing -= 0.125 if @battle.FE == :CORROSIVE && (attacker.ability == :GRASSPELT || attacker.ability == :LEAFGUARD || attacker.ability == :FLOWERVEIL)
      healing -= 0.125 if @battle.FE == :INFERNAL && attacker.effects[:Torment]

      # weather induced
      healing -= 0.125 if @battle.pbWeather == :SUNNYDAY && (attacker.ability == :SOLARPOWER || attacker.ability == :DRYSKIN)
      healing -= 0.125 if @battle.pbWeather == :SUNNYDAY && (attacker.crested == :CASTFORM && attacker.form == 1)
      healing -= (Rejuv && @battle.FE == :DESERT) ? 0.125 : 0.0625 if @battle.pbWeather == :SANDSTORM && (!(attacker.hasType?(:GROUND) || attacker.hasType?(:ROCK) || attacker.hasType?(:STEEL) || [:SANDFORCE,:SANDRUSH,:SANDVEIL,:MAGICGUARD,:OVERCOAT,:TEMPEST].include?(attacker.ability)) || attacker.effects[:DesertsMark])
      # Gen 9 Mod - Hail/Snow/Both
      healing -= (@battle.FE == :FROZENDIMENSION) ? 0.125 : 0.0625 if @battle.pbWeather == :HAIL && !(attacker.hasType?(:ICE) || [:SNOWCLOAK,:ICEBODY,:LUNARIDOL,:SLUSHRUSH,:MAGICGUARD,:OVERCOAT,:TEMPEST].include?(attacker.ability) || HAILSNOWMOD == "Snow") || KAIZOMOD
      healing -= (@battle.FE == :DIMENSIONAL || @battle.FE == :FROZENDIMENSION) ? 0.125 : 0.0625 if (@battle.pbWeather== :SHADOWSKY && !@attacker.hasType?(:SHADOW))

      # Status induced
      healing -= 0.125 if attacker.status == :POISON && attacker.ability != :POISONHEAL && attacker.crested != :ZANGOOSE && attacker.statusCount==0
      healing -= [15,attacker.effects[:Toxic]].min / 16.0 if attacker.status == :POISON && attacker.ability != :POISONHEAL && attacker.crested != :ZANGOOSE  && attacker.statusCount > 0
      healing -= 0.0625 if attacker.status == :BURN
      if attacker.status == :SLEEP || (attacker.ability == :COMATOSE && @battle.FE != :ELECTERRAIN)
        sleepdmg =  (@battle.FE == :DIMENSIONAL || @battle.FE == :BEWITCHED || @battle.FE == :SWAMP) ? 0.0625 : 0.0
        # rejuv specific swamp field mechanic
        if Rejuv &&  @battle.FE == :SWAMP
          sleepdmg *= 2.0 if attacker.effects[:MultiTurn] > 0
        end
        if (attacker.pbOpposing1.ability == :BADDREAMS || attacker.pbOpposing2.ability == :BADDREAMS) && @battle.FE != :RAINBOW
          if @battle.FE == :INFERNAL || @battle.FE == :DARKNESS3
            sleepdmg += 0.25
          elsif @battle.FE == :DARKNESS2
            sleepdmg += 0.166
          else
            sleepdmg += 0.125
          end
        end
        healing -= sleepdmg
      end
      healing -= 0.0625 if attacker.status == :SLEEP && (@battle.FE == :DIMENSIONAL || @battle.FE == :BEWITCHED)

      # Other
      healing -= 0.125 if attacker.effects[:LeechSeed]>=0 && attacker.ability != :LIQUIDOOZE
      healing -= 0.125 if attacker.status == :PETRIFIED && attacker.ability != :LIQUIDOOZE
      healing -= 0.125 if @battle.FE == :WASTELAND && attacker.effects[:LeechSeed]>=0 && attacker.ability != :LIQUIDOOZE
      healing -= (@battle.FE == :DARKNESS3 || @battle.FE == :HAUNTED) ? 0.33 : 0.25 if attacker.effects[:Nightmare] && @battle.FE != :RAINBOW && attacker.status== :SLEEP
      healing -= 0.3 if attacker.effects[:Curse] && @battle.FE != :HOLY
      # Gen 9 Mod - Taking damage if attacker is being Salt Cured.
      healing -= 0.125 if attacker.effects[:SaltCure]
      healing -= 0.125 if attacker.effects[:SaltCure] && (attacker.hasType?(:WATER) || attacker.hasType?(:STEEL))
      if attacker.effects[:MultiTurn] > 0
        if attacker.effects[:BindingBand]
          healing -= 0.1667
        else
          case attacker.effects[:MultiTurnAttack]
          when :FIRESPIN then healing -= (@battle.FE == :BURNING || @battle.FE == :HAUNTED) ? 0.1667 : 0.125
          when :MAGMASTORM then healing -= @battle.FE == :DRAGONSDEN ? 0.1667 : 0.125
          when :SANDTOMB then healing -= @battle.FE == :DESERT ? 0.1667 : 0.125
          when :WHIRLPOOL then healing -= (@battle.FE == :WATERSURFACE || @battle.FE == :UNDERWATER) ? 0.1667 : 0.125
          when :THUNDERCAGE then healing -= @battle.FE == :ELECTERRAIN ? 0.1667 : 0.125
          when :SNAPTRAP then healing -= @battle.FE == :GRASSY ? 0.1667 : 0.125
          when :INFESTATION
            if @battle.FE == :FOREST || @battle.FE == :FLOWERGARDEN3
              healing -= 0.1667
            elsif @battle.FE == :FLOWERGARDEN4
              healing -= 0.25
            elsif @battle.FE == :FLOWERGARDEN5
              healing -= 0.33
            else
              healing -= 0.125
            end
          else healing -= 0.125
          end
        end
      end
      healing -= 0.125 if attacker.item == :STICKYBARB
      healing -= @battle.FE == :CORRUPTED ? 0.25 : 0.125 if (attacker.item == :BLACKSLUDGE && !attacker.hasType?(:POISON))
    end
    healing = 0 if healing < 0

    # Positive healing effects
    return healing if attacker.effects[:HealBlock]!=0
    if attacker.effects[:AquaRing]
      subscore = 0
      subscore = 0.0625 if !(@battle.FE == :CORROSIVEMIST && !attacker.hasType?(:STEEL) && !attacker.hasType?(:POISON))
      if Rejuv && @battle.FE == :GRASSY
        subscore *= 1.6 if attacker.itemWorks? && attacker.item == :BIGROOT
      else
        subscore *= 1.3 if attacker.itemWorks? && attacker.item == :BIGROOT
      end
      subscore *= 1.3 if (@attacker.crested == :SHIINOTIC)
      subscore *= 2.0 if @battle.FE == :MISTY || @battle.FE == :SWAMP || @battle.FE == :WATERSURFACE || @battle.FE == :UNDERWATER
      healing += subscore
    end
    if attacker.effects[:Ingrain]
      subscore = 0
      subscore = 0.0625 if @battle.FE != :SWAMP && @battle.FE != :CORROSIVE
      subscore = 0.0625 if (@battle.FE == :SWAMP || @battle.FE == :CORROSIVE) && (attacker.hasType?(:STEEL) && attacker.hasType?(:POISON))
      if Rejuv && @battle.FE == :GRASSY
        subscore *= 1.6 if attacker.itemWorks? && attacker.item == :BIGROOT
      else
        subscore *= 1.3 if attacker.itemWorks? && attacker.item == :BIGROOT
      end
      subscore *= 1.3 if (@attacker.crested == :SHIINOTIC)
      subscore *= 2.0 if (@battle.FE == :FOREST || @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN) || (Rejuv && @battle.FE == :GRASSY)) || @battle.state.effects[:GRASSY] > 0
      subscore *= 2.0 if (@battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN,4,5))
      healing += subscore
    end
    if attacker.ability == :DRYSKIN
      healing += 0.0625 if ((@battle.FE == :CORROSIVE || @battle.FE == :CORRUPTED) && attacker.hasType?(:POISON) && !attacker.hasType?(:STEEL)) || @battle.pbWeather== :RAINDANCE || [:MISTY,:SWAMP,:WATERSURFACE,:UNDERWATER].include?(@battle.FE) || @battle.state.effects[:MISTY] > 0
    end
    healing += @battle.FE == :CORRUPTED ? 0.125 : 0.0625 if attacker.itemWorks? && (attacker.item == :BLACKSLUDGE && attacker.hasType?(:POISON))
    healing += 0.0625 if attacker.itemWorks? && attacker.item == :LEFTOVERS
    healing += 0.0625 if attacker.crested == :INFERNAPE
    healing += 0.0625 if attacker.crested == :GOTHITELLE && attacker.type1 == :PSYCHIC
    healing += 0.0625 if attacker.crested == :VESPIQUEN && attacker.effects[:VespiCrest] == false
    healing += (attacker.pbEnemyFaintedPokemonCount*0.05) if attacker.crested == :SPIRITOMB
    healing += 0.125 if attacker.ability == :RAINDISH && @battle.pbWeather== :RAINDANCE
    healing += 0.0625 if (attacker.crested == :CASTFORM && attacker.form == 2) && @battle.pbWeather== :RAINDANCE
    healing += 0.125 if attacker.ability == :ICEBODY && (@battle.pbWeather== :HAIL || @battle.FE == :ICY || @battle.FE == :SNOWYMOUNTAIN || @battle.FE == :FROZENDIMENSION)
    healing += 0.125 if attacker.crested == :DRUDDIGON && @battle.pbWeather== :SUNNYDAY
    healing += 0.0625 if attacker.crested == :MEGANIUM || attacker.pbPartner.crested == :MEGANIUM
    healing += 0.125 if (attacker.status == :POISON || @battle.FE == :CORROSIVE || @battle.FE == :WASTELAND) && (attacker.ability == :POISONHEAL || attacker.crested == :ZANGOOSE)
    healing += 0.0625 if Rejuv && (@battle.FE == :GRASSY || @battle.state.effects[:GRASSY] > 0) && attacker.ability == :SAPSIPPER
    healing += 0.0625 if (@battle.FE == :GRASSY || @battle.state.effects[:GRASSY] > 0) && !attacker.isAirborne? && !PBStuff::TWOTURNMOVE.include?(attacker.effects[:TwoTurnAttack])
    healing += 0.0625 if Rejuv && (@battle.FE == :ELECTERRAIN || @battle.state.effects[:ELECTERRAIN ] > 0) && attacker.ability == :VOLTABSORB
    if @battle.FE != :INDOOR
      healing += 0.0625 if @battle.FE == :RAINBOW && attacker.status == :SLEEP
      healing += 0.0625 if @battle.FE == :FOREST && attacker.ability == :SAPSIPPER
      healing += 0.0625 if @battle.FE == :SHORTCIRCUIT && attacker.ability == :VOLTABSORB
      healing += 0.125 if (@battle.FE == :WATERSURFACE || @battle.FE == :UNDERWATER || @battle.FE == :SWAMP) && attacker.ability == :WATERABSORB
      healing += 0.0625 if @battle.FE == :BEWITCHED && attacker.hasType?(:GRASS) && !attacker.isAirborne?
      healing *= 0.67 if @battle.FE == :BACKALLEY
    end
    return healing
  end

  def pbPartyHasType?(type,index=@index)
    typevar=false
    for mon in @battle.pbParty(index)
      next if mon.nil? || mon.isEgg?
      typevar=true if mon.hp > 0 && mon.hasType?(type)
    end
    return typevar
  end

  def illusionCheck(attacker = @attacker, opponent = @opponent)
    return false if opponent.index == attacker.pbPartner.index
    return false unless opponent.effects[:Illusion]

    deceived = false
    faintedcount = 0
    for i in @battle.pbPartySingleOwner(opponent.index)
      next if i.nil?

      faintedcount += 1 if i.hp == 0
    end
    if @mondata.skill >= BESTSKILL
      deceived = opponent.turncount <= 1 && faintedcount <= 2
      if $cache.moves[opponent.lastMoveTaken]
        move = PokeBattle_Move.pbFromPBMove(@battle, PBMove.new(opponent.lastMoveTaken.intern), @attacker)
        typemod = move.pbTypeModifier(move.type, attacker, opponent, false)
        typemod = move.irregularTypeMods(attacker, opponent, typemod, move.type)
        typemod = move.fieldTypeChange(attacker, opponent, typemod, false)
        typemod = move.overlayTypeChange(attacker, opponent, typemod, false)
        deceived = false if opponent.turncount >= 0 && !attacker.missAcc && !attacker.effects[:Tantrum] && move.basedamage > 0 && typemod == 0
      end
    elsif @mondata.skill >= MEDIUMSKILL
      deceived = faintedcount <= 4
    else
      deceived = true
    end
    return deceived
  end

  def pbTypeModNoMessages(type=@move.type,attacker=@attacker,opponent=@opponent,move=@move,skill=@mondata.skill)
    return 4 if !type
    id = move.move
    secondtype = move.getSecondaryType(attacker)
    if !(moldBreakerCheck(attacker) || myceliumMightCheck(attacker, move)) # Gen 9 Mod - Added myceliumMightCheck
      case opponent.ability
        when :SAPSIPPER              then return -1 if type == :GRASS || (!secondtype.nil? && secondtype.include?(:GRASS))
        when :LEVITATE,:SOLARIDOL,:LUNARIDOL   then return 0 if (type == :GROUND || (!secondtype.nil? && secondtype.include?(:GROUND))) && @battle.FE != :CAVE && !opponent.hasWorkingItem(:IRONBALL) && @battle.state.effects[:Gravity]==0
        when :MAGNETPULL,:CONTRARY,:UNAWARE,:OBLIVIOUS   then return 0 if (type == :GROUND || (!secondtype.nil? && secondtype.include?(:GROUND))) && @battle.FE == :DEEPEARTH && !opponent.hasWorkingItem(:IRONBALL)
        when :STORMDRAIN             then return -1 if type == :WATER || (!secondtype.nil? && secondtype.include?(:WATER))
        when :LIGHTNINGROD,:MOTORDRIVE      then return -1 if type == :ELECTRIC || (!secondtype.nil? && secondtype.include?(:ELECTRIC))
        when :DRYSKIN               then return -1 if type == :WATER || (!secondtype.nil? && secondtype.include?(:WATER)) && opponent.effects[:HealBlock] ==0
        when :VOLTABSORB             then return -1 if type == :ELECTRIC || (!secondtype.nil? && secondtype.include?(:ELECTRIC)) && opponent.effects[:HealBlock] ==0
        when :WATERABSORB             then return -1 if type == :WATER || (!secondtype.nil? && secondtype.include?(:WATER)) && opponent.effects[:HealBlock] ==0
        # Gen 9 Mod - Added Earth Eater
        when :EARTHEATER             then return -1 if type == :GROUND || (!secondtype.nil? && secondtype.include?(:GROUND)) && opponent.effects[:HealBlock] ==0
        when :BULLETPROOF             then return 0 if (PBStuff::BULLETMOVE).include?(id)
        when :FLASHFIRE             then return -1 if type == :FIRE || (!secondtype.nil? && secondtype.include?(:FIRE))
        when :MAGMAARMOR             then return 0 if (type == :FIRE || (!secondtype.nil? && secondtype.include?(:FIRE))) && (@battle.FE == :DRAGONSDEN || @battle.FE == :INFERNAL || @battle.FE == :VOLCANICTOP)
        when :TELEPATHY             then return 0 if  move.basedamage>0 && opponent.index == attacker.pbPartner.index
      end
    end
    case opponent.crested
      when :WHISCASH then return -1 if type == :GRASS || (!secondtype.nil? && secondtype.include?(:GRASS))
      when :SKUNTANK then return -1 if type == :GROUND || (!secondtype.nil? && secondtype.include?(:GROUND))
      when :DRUDDIGON then return -1 if type == :FIRE || (!secondtype.nil? && secondtype.include?(:FIRE))
    end
    if @battle.FE == :ROCKY && (opponent.effects[:Substitute] > 0 || opponent.stages[PBStats::EVASION] > 0)
      return 0 if PBStuff::BULLETMOVE.include?(id)
    end
    if (@battle.FE == :WATERSURFACE || @battle.FE == :MURKWATERSURFACE) && (type == :GROUND || (!secondtype.nil? && secondtype.include?(:GROUND)))
      return 0
    end
    if @battle.FE == :HOLY && move.basedamage > 0 && opponent.index == attacker.pbPartner.index
      return 0
    end
    if Rejuv && @battle.FE == :DESERT && @battle.pbWeather == :SUNNYDAY && (type == :WATER || (!secondtype.nil? && secondtype.include?(:WATER))) && (opponent.hasType?(:WATER) || opponent.hasType?(:GRASS)) && opponent.effects[:HealBlock] == 0
      return -1
    end

    if Rejuv && @battle.FE == :GLITCH && opponent.species == :GENESECT
      if opponent.item == :BURNDRIVE && (type == :FIRE || (!secondtype.nil? && secondtype.include?(:FIRE)))
        return -1
      elsif opponent.item == :DOUSEDRIVE && (type == :WATER || (!secondtype.nil? && secondtype.include?(:WATER)))
        return -1
      elsif opponent.item == :CHILLDRIVE && (type == :ICE || (!secondtype.nil? && secondtype.include?(:ICE)))
        return -1
      elsif opponent.item == :SHOCKDRIVE && (type == :ELECTRIC || (!secondtype.nil? && secondtype.include?(:ELECTRIC)))
        return -1
      end
    end
    typemod = move.pbTypeModifier(type, attacker, opponent)
    typemod = move.irregularTypeMods(attacker, opponent, typemod, type)

    if id == :FLYINGPRESS
      if @battle.FE == :SKY
        typemod *= 2 if $game_switches[:Inversemode] ? PBTypes.oneTypeEff(:FLYING, opponent.type1) > 2 : PBTypes.oneTypeEff(:FLYING, opponent.type1) < 2
        typemod *= 2 if $game_switches[:Inversemode] ? PBTypes.oneTypeEff(:FLYING, opponent.type2) > 2 : PBTypes.oneTypeEff(:FLYING, opponent.type2) < 2
      else
        typemod2 = move.pbTypeModifier(:FLYING, attacker, opponent)
        typemod2 = move.irregularTypeMods(attacker, opponent, typemod2, :FLYING)
        typemod = (typemod * typemod2) / 4
      end
    end

    # Field Effect type changes go here
    typemod = move.fieldTypeChange(attacker, opponent, typemod, false)
    typemod = move.overlayTypeChange(attacker, opponent, typemod, false)
    typemod = 0 if opponent.ability == :WONDERGUARD && !moldBreakerCheck(attacker) && typemod <= 4

    return 1 if typemod == 0 && move.function == 0x111

    return typemod
  end

  #@scorearray = [[-1,-1,-1,-1],[-1,-1,-1,-1],[-1,-1,-1,-1],[-1,-1,-1,-1]]
  def getMaxScoreIndex(scores)
    maxscore=scores.max {|a,b| a.max <=> b.max}
    maxscoreindex = scores.find_index {|score| score == maxscore}
    return [maxscoreindex,scores[maxscoreindex].find_index {|score| score == scores[maxscoreindex].max}]
  end

  def pbChangeMove(move,attacker)
    return move unless [:WEATHERBALL, :HIDDENPOWER, :TERRAINPULSE, :NATUREPOWER, :IVYCUDGEL, :RAGINGBULL, :TERASTARSTORM].include?(move.move) # Gen 9 Mod - Added Ivy Cudgel, Raging Bull and Tera Starstorm

    attacker = @opponent if caller_locations.any? {|call| call.label=="buildMoveScores"} && attacker.nil?
    #make new instance of move
    move = PokeBattle_Move.pbFromPBMove(@battle,PBMove.new(move.move),attacker)
    case move.move
      when :WEATHERBALL
        weather = @battle.pbWeather
        move.type = :NORMAL
        move.type = :FIRE if weather == :SUNNYDAY && !attacker.hasWorkingItem(:UTILITYUMBRELLA)
        move.type = :WATER if weather == :RAINDANCE && !attacker.hasWorkingItem(:UTILITYUMBRELLA)
        move.type = :ROCK if weather == :SANDSTORM
        move.type = :ICE if weather == :HAIL
        move.basedamage*=2 if @battle.pbWeather !=0 || @battle.FE == :RAINBOW && move.basedamage == 50

      when :HIDDENPOWER
        move.type = move.pbType(attacker) if attacker
      when :TERRAINPULSE
        move.type = @battle.field.mimicry if @battle.field.mimicry
      when :NATUREPOWER
        move = PokeBattle_Move.pbFromPBMove(@battle, PBMove.new(@battle.field.naturePower), attacker)
        move.priority = 1 if attacker.ability == :PRANKSTER
      when :IVYCUDGEL
        move.type = :WATER if (attacker.species == :OGERPON && attacker.item == :WELLSPRINGMASK)
        move.type = :FIRE if (attacker.species == :OGERPON && attacker.item == :HEARTHFLAMEMASK)
        move.type = :ROCK if (attacker.species == :OGERPON && attacker.item == :CORNERSTONEMASK)
      when :RAGINGBULL
        move.type = :FIGHTING if (attacker.species == :TAUROS && attacker.form == 1)
        move.type = :FIRE if (attacker.species == :TAUROS && attacker.form == 2)
        move.type = :WATER if (attacker.species == :TAUROS && attacker.form == 3)
      when :TERASTARSTORM
        move.type = :STELLAR if (attacker.species == :TERAPAGOS && attacker.form == 2)
    end
    return move
  end

  def scoreDecrease(threat_index, killable, decreased_by, ai_leader)
    if killable[ai_leader] == :both
      # changing scoring for leader on mon that the leader doesn't kill
      @aimondata[ai_leader].scorearray[threat_index^2].map! {|score| score>80 ? 80 : score }
      # decreasing score for follower on mon that the leader kills
      @aimondata[ai_leader^2].scorearray[threat_index].map! {|score| score * decreased_by}
    elsif killable[ai_leader] == :left
      @aimondata[ai_leader^2].scorearray[0].map! {|score| score * decreased_by}
    elsif killable[ai_leader] == :right
      @aimondata[ai_leader^2].scorearray[2].map! {|score| score * decreased_by}
    end
  end

  def totalHazardDamage(pkmn)
    percentdamage = 0
    if pkmn.pbOwnSide.effects[:Spikes]>0 && !pkmn.isAirborne? && !pkmn.ability == :MAGICGUARD && !(pkmn.ability == :WONDERGUARD && @battle.FE == :COLOSSEUM) && !pkmn.hasWorkingItem(:HEAVYDUTYBOOTS)
      spikesdiv=[8,8,6,4][pkmn.pbOwnSide.effects[:Spikes]]
      if Rejuv && @battle.FE == :ELECTERRAIN && @mondata.skill>BESTSKILL
              eff=PBTypes.twoTypeEff(:ELECTRIC,pkmn.type1,pkmn.type2)
              if eff>0
        percentdamage += 100*eff/4*spikesdiv
              end
      else
        percentdamage += (100.0/spikesdiv).floor
      end
    end
    if pkmn.pbOwnSide.effects[:StealthRock] && !pkmn.ability == :MAGICGUARD && !(pkmn.ability == :WONDERGUARD && @battle.FE == :COLOSSEUM) && !pkmn.hasWorkingItem(:HEAVYDUTYBOOTS)
      eff=PBTypes.twoTypeEff(:ROCK,pkmn.type1,pkmn.type2)
      if @mondata.skill>BESTSKILL && @battle.FE == :CRYSTALCAVERN
        eff1=PBTypes.twoTypeEff(:WATER,pkmn.type1,pkmn.type2)
        eff2=PBTypes.twoTypeEff(:GRASS,pkmn.type1,pkmn.type2)
        eff3=PBTypes.twoTypeEff(:FIRE,pkmn.type1,pkmn.type2)
        eff4=PBTypes.twoTypeEff(:PSYCHIC,pkmn.type1,pkmn.type2)
        eff = [eff1,eff2,eff3,eff4].max
      elsif @mondata.skill>BESTSKILL && @battle.FE == :CORRUPTED
        eff=PBTypes.twoTypeEff(:POISON,pkmn.type1,pkmn.type2)
      elsif @mondata.skill>BESTSKILL && (@battle.FE == :VOLCANICTOP || @battle.FE == :INFERNAL || (Rejuv && @battle.FE == :DRAGONSDEN))
        eff=PBTypes.twoTypeEff(:FIRE,pkmn.type1,pkmn.type2) # Gen 9 Mod - Ported fix from Reborn 19.5
      end
      if eff>0
        eff*=2 if @mondata.skill>BESTSKILL && (@battle.FE == :ROCKY || @battle.FE == :CAVE)
        percentdamage += 100*(eff/32.0)
      end
    end
    if @mondata.skill>=BESTSKILL
      # Corrosive Field Entry
      if @battle.FE == :CORROSIVE
        if ![:MAGICGUARD, :POISONHEAL, :IMMUNITY, :WONDERGUARD, :TOXICBOOST, :PASTELVEIL].include?(pkmn.ability) && pkmn.crested != :ZANGOOSE
          if !pkmn.isAirborne? && !pkmn.hasType?(:POISON) && !pkmn.hasType?(:STEEL)
            eff=PBTypes.twoTypeEff(:POISON,pkmn.type1,pkmn.type2)
            eff*=2
            percentdamage += 100*(eff/32.0)
          end
        end
      # Icy field + Seed activation spike damage
      elsif @battle.FE == :ICY
        if pkmn.item == :ELEMENTALSEED && pkmn.ability != :KLUTZ && !pkmn.isAirborne? && pkmn.ability != :MAGICGUARD
          spikesdiv=[8,8,6,4][pkmn.pbOwnSide.effects[:Spikes]]
          percentdamage += (100.0/spikesdiv).floor
        end
      # Cave field + Seed activation stealth rock damage
      elsif @battle.FE == :CAVE
        if pkmn.item == :TELLURICSEED && pkmn.ability != :KLUTZ && pkmn.ability != :MAGICGUARD
          eff=PBTypes.twoTypeEff(:ROCK,pkmn.type1,pkmn.type2)
          if eff>0
            eff = eff*2
            percentdamage += 100*(eff/32.0)
          end
        end
      elsif @battle.FE == :CONCERT3 || @battle.FE == :CONCERT4
        if pkmn.status == :SLEEP || pkmn.ability == :COMATOSE
          percentdamage += 25
        end
      end
    end
    return percentdamage
  end

  def getAbilityDisruptScore(attacker,opponent)
    abilityscore=100.0
    return (abilityscore/100) if opponent.ability.nil? #if the ability doesn't work, then nothing here matters
    return 0 if PBStuff::FIXEDABILITIES.include?(opponent.ability) # Gen 9 Mod - Ported change from Reborn 19.5
    case opponent.ability
      when :SPEEDBOOST
        abilityscore*=1.1
        abilityscore*=1.3 if opponent.stages[PBStats::SPEED]<2
      when :SANDVEIL
        abilityscore*=1.3 if @battle.pbWeather== :SANDSTORM
      when :VOLTABSORB, :LIGHTNINGROD, :MOTORDRIVE
        for i in attacker.moves
          next if i.nil?
          elecmove=i if i.pbType(attacker)==:ELECTRIC
        end
        if attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.pbType(attacker) == :ELECTRIC}
          abilityscore*=3 if attacker.moves.all? {|moveloop| moveloop!=nil && moveloop.pbType(attacker) == :ELECTRIC}
          abilityscore*=2 if pbTypeModNoMessages(elecmove.pbType(attacker),attacker,opponent,elecmove)>4
        end
      when :WATERABSORB, :STORMDRAIN, :DRYSKIN
        for i in attacker.moves
          next if i.nil?
          watermove=i if i.pbType(attacker)==:WATER
        end
        if attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.pbType(attacker) == :WATER}
          abilityscore*=3 if attacker.moves.all? {|moveloop| moveloop!=nil && moveloop.pbType(attacker) == :WATER}
          abilityscore*=2 if pbTypeModNoMessages(watermove.pbType(attacker),attacker,opponent,watermove)>4
        end
        abilityscore*=0.5 if opponent.ability == :DRYSKIN && attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.pbType(attacker) == :FIRE}
      when :SAPSIPPER
        for i in attacker.moves
          next if i.nil?
          grassmove=i if i.pbType(attacker) == :GRASS
        end
        if attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.pbType(attacker) == :GRASS}
          abilityscore*=3 if attacker.moves.all? {|moveloop| moveloop!=nil && moveloop.pbType(attacker) == :GRASS}
          abilityscore*=2 if pbTypeModNoMessages(grassmove.pbType(attacker),attacker,opponent,grassmove)>4
        end
      when :FLASHFIRE
        for i in attacker.moves
          next if i.nil?
          firemove=i if i.pbType(attacker) == :FIRE
        end
        if attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.pbType(attacker) == :FIRE}
          abilityscore*=3 if attacker.moves.all? {|moveloop| moveloop!=nil && moveloop.pbType(attacker) == :FIRE}
          abilityscore*=2 if pbTypeModNoMessages(firemove.pbType(attacker),attacker,opponent,firemove)>4
        end
      when :LEVITATE, :LUNARIDOL, :SOLARIDOL, :EARTHEATER # Gen 9 Mod - Added Earth Eater
        for i in attacker.moves
          next if i.nil?
          groundmove=i if i.pbType(attacker) == :GROUND
        end
        if attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.pbType(attacker) == :GROUND}
          abilityscore*=3 if attacker.moves.all? {|moveloop| moveloop!=nil && moveloop.pbType(attacker) == :GROUND}
          abilityscore*=2 if pbTypeModNoMessages(groundmove.pbType(attacker),attacker,opponent,groundmove)>4
        end
      when :SHADOWTAG
        abilityscore*=1.5 if (!attacker.hasType?(:GHOST) || @battle.FE == :DIMENSIONAL)
      when :ARENATRAP
        abilityscore*=1.5 if attacker.isAirborne?
      when :WONDERGUARD
        abilityscore*=5 if !attacker.moves.any? {|moveloop| moveloop!=nil && pbTypeModNoMessages(moveloop.pbType(attacker),attacker,opponent,moveloop)>4}
      when :SERENEGRACE
        abilityscore*=1.3
      when :PUREPOWER, :HUGEPOWER
        abilityscore*=2
      when :SOUNDPROOF
        abilityscore*=3 if attacker.moves.all? {|moveloop| moveloop!=nil && (moveloop.isSoundBased? || moveloop.basedamage==0)}
      when :THICKFAT
        abilityscore*=1.5 if attacker.moves.all? {|moveloop| moveloop!=nil && (moveloop.pbType(attacker) == :FIRE || moveloop.pbType(attacker) == :ICE) }
      when :TRUANT
        abilityscore*=0.1
      when :GUTS, :QUICKFEET, :MARVELSCALE
        abilityscore*=1.5 if !opponent.status.nil?
      when :LIQUIDOOZE
        abilityscore*=2 if opponent.effects[:LeechSeed]>=0 || attacker.pbHasMove?(:LEECHSEED)
      when :AIRLOCK, :CLOUDNINE
        abilityscore*=1.1
      when :HYDRATION
        abilityscore*=1.3 if hydrationCheck(attacker)
      when :ADAPTABILITY
        abilityscore*=1.3
      when :SKILLLINK
        abilityscore*=1.5
      when :POISONHEAL
        abilityscore*=2 if opponent.status== :POISON
      when :NORMALIZE
        abilityscore*=0.6
      when :MAGICGUARD
        abilityscore*=1.4
      when :STALL
        abilityscore*=0.5
      when :TECHNICIAN
        abilityscore*=1.3
      when :MOLDBREAKER, :TERAVOLT, :TURBOBLAZE
        abilityscore*=1.1
      when :UNAWARE
        abilityscore*=1.7
      when :SLOWSTART
        abilityscore*=0.3
      when :SHEERFORCE
        abilityscore*=1.2
      when :CONTRARY
        abilityscore*=1.4
        abilityscore*=2 if opponent.stages[PBStats::ATTACK]>0 || opponent.stages[PBStats::SPATK]>0 || opponent.stages[PBStats::DEFENSE]>0 || opponent.stages[PBStats::SPDEF]>0 || opponent.stages[PBStats::SPEED]>0
      when :DEFEATIST
        abilityscore*=0.5
      when :MULTISCALE
        abilityscore*=1.5 if opponent.hp==opponent.totalhp
      when :TERASHELL # Gen 9 Mod - Tera Shell same consideration as Multiscale
        abilityscore*=1.5 if opponent.hp==opponent.totalhp
      when :HARVEST
        abilityscore*=1.2
      when :MOODY
        abilityscore*=1.8
      when :PRANKSTER
        abilityscore*=1.5 if pbAIfaster?(nil,nil,attacker,opponent)
      when :SNOWCLOAK
        abilityscore*=1.1 if @battle.pbWeather== :HAIL
      when :FURCOAT
        abilityscore*=1.5 if attacker.attack>attacker.spatk
      when :PARENTALBOND
        abilityscore*=3
      when :PROTEAN, :LIBERO
        abilityscore*=3
      when :TOUGHCLAWS
        abilityscore*=1.2
      when :BEASTBOOST
        abilityscore*=1.1
      when :COMATOSE
        abilityscore*=1.3
      when :FLUFFY
        abilityscore*=1.5
        abilityscore*=0.5 if attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.pbType(attacker)==:FIRE}
      when :MERCILESS
        abilityscore*=1.3
      when :WATERBUBBLE
        abilityscore*=1.5
        abilityscore*=1.3 if attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.pbType(attacker)==:FIRE}
      when :WELLBAKEDBODY # Gen 9 Mod - Added Well-Baked Body
        abilityscore*=3 if attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.pbType(attacker)==:FIRE}
      when :WINDPOWER # Gen 9 Mod - Added Wind Power
        abilityscore*=1.3 if attacker.moves.all? {|moveloop| moveloop!=nil && (moveloop.windMove?)}
      when :WINDRIDER # Gen 9 Mod - Added Wind Rider
        abilityscore*=3 if attacker.moves.all? {|moveloop| moveloop!=nil && (moveloop.windMove?)}
      when :ICESCALES
        abilityscore*=1.5 if attacker.spatk>attacker.attack
      when :MYCELIUMMIGHT # Gen 9 Mod - Added Mycelium Might
        abilityscore*=1.5
      when :CUDCHEW # Gen 9 Mod - Added Cud Chew
        abilityscore*=1.2
        # Kaizo Mod below
      when :TECHLINK
        abilityscore*=1.5 * 1.3
      else
        if attacker.pbPartner==opponent && abilityscore!=0
          abilityscore=200 if abilityscore>200
          tempscore = abilityscore
          abilityscore = 200 - tempscore
        end
    end
    abilityscore*=0.01
    return abilityscore
  end

  def getFieldDisruptScore(attacker=@attacker,opponent=@opponent,fieldeffect=@battle.FE, violent=false)
    fieldscore=100.0
    aroles = pbGetMonRoles(attacker)
    oroles = pbGetMonRoles(opponent)
    aimem = getAIMemory(opponent)
    case fieldeffect
      when :INDOOR # No field
      when :ELECTERRAIN # Electric Terrain
        fieldscore*=1.5 if opponent.hasType?(:ELECTRIC) || opponent.pbPartner.hasType?(:ELECTRIC)
        fieldscore*=0.5 if attacker.hasType?(:ELECTRIC)
        fieldscore*=0.5 if pbPartyHasType?(:ELECTRIC)
        fieldscore*=1.3 if opponent.ability == :SURGESURFER
        fieldscore*=0.7 if attacker.ability == :SURGESURFER
        # Gen 9 Mod - Added Hadron Engine
        fieldscore*=1.5 if opponent.ability == :HADRONENGINE
        fieldscore*=0.7 if attacker.ability == :HADRONENGINE
      when :GRASSY # Grassy Terrain
        fieldscore*=1.5 if opponent.hasType?(:GRASS) || opponent.pbPartner.hasType?(:GRASS)
        fieldscore*=0.5 if attacker.hasType?(:GRASS)
        fieldscore*=1.8 if opponent.hasType?(:FIRE) || opponent.pbPartner.hasType?(:FIRE)
        fieldscore*=0.2 if attacker.hasType?(:FIRE)
        fieldscore*=0.5 if pbPartyHasType?(:GRASS)
        fieldscore*=0.2 if pbPartyHasType?(:FIRE)
        fieldscore*=1.3 if attacker.hasType?(:WATER)
        fieldscore*=1.5 if pbPartyHasType?(:WATER)
        fieldscore*=0.8 if aroles.include?(:SPECIALWALL) || aroles.include?(:PHYSICALWALL)
        fieldscore*=1.2 if oroles.include?(:SPECIALWALL) || oroles.include?(:PHYSICALWALL)
      when :MISTY # Misty Terrain
        fieldscore*=1.3 if attacker.spatk>attacker.attack && (opponent.hasType?(:FAIRY) || opponent.pbPartner.hasType?(:FAIRY))
        fieldscore*=0.7 if attacker.hasType?(:FAIRY) && opponent.spatk>opponent.attack
        fieldscore*=0.5 if opponent.hasType?(:DRAGON) || opponent.pbPartner.hasType?(:DRAGON)
        fieldscore*=1.5 if attacker.hasType?(:DRAGON)
        fieldscore*=0.7 if pbPartyHasType?(:FAIRY)
        fieldscore*=1.5 if pbPartyHasType?(:DRAGON)
        fieldscore*=1.8 if @battle.field.counter==1 && (!(attacker.hasType?(:POISON) || attacker.hasType?(:STEEL)))
      when :DARKCRYSTALCAVERN # Dark Crystal Cavern
        fieldscore*=1.3 if opponent.hasType?(:DARK) || opponent.pbPartner.hasType?(:DARK) || opponent.hasType?(:GHOST) || opponent.pbPartner.hasType?(:GHOST)
        fieldscore*=0.7 if attacker.hasType?(:DARK) || attacker.hasType?(:GHOST)
        fieldscore*=0.7 if pbPartyHasType?(:DARK) || pbPartyHasType?(:GHOST)
      when :CHESS # Chess field
        fieldscore*=1.3 if opponent.hasType?(:PSYCHIC) || opponent.pbPartner.hasType?(:PSYCHIC)
        fieldscore*=0.7 if attacker.hasType?(:PSYCHIC)
        fieldscore*=0.7 if pbPartyHasType?(:PSYCHIC)
        fieldscore*= attacker.pbSpeed>opponent.pbSpeed ? 1.3 : 0.7
      when :BIGTOP # Big Top field
        fieldscore*=1.5 if opponent.hasType?(:FIGHTING) || opponent.pbPartner.hasType?(:FIGHTING)
        fieldscore*=0.5 if attacker.hasType?(:FIGHTING)
        fieldscore*=0.5 if pbPartyHasType?(:FIGHTING)
        fieldscore*=1.5 if opponent.ability == :DANCER
        fieldscore*=0.5 if attacker.ability == :DANCER
        fieldscore*=0.5 if attacker.pbHasMove?(:SING) || attacker.pbHasMove?(:DRAGONDANCE) || attacker.pbHasMove?(:QUIVERDANCE)
        fieldscore*=1.5 if checkAImoves([:SING,:DRAGONDANCE,:QUIVERDANCE],aimem)
      when :BURNING # Burning Field
        fieldscore*=1.8 if opponent.hasType?(:FIRE) || opponent.pbPartner.hasType?(:FIRE)
        if attacker.hasType?(:FIRE)
          fieldscore*=0.2
        else
          fieldscore*=1.5
          fieldscore*=1.8 if attacker.hasType?(:GRASS) || attacker.hasType?(:ICE) || attacker.hasType?(:BUG) || attacker.hasType?(:STEEL)
        end
        fieldscore*=0.2 if pbPartyHasType?(:FIRE)
        fieldscore*=1.5 if pbPartyHasType?(:GRASS) || pbPartyHasType?(:ICE) || pbPartyHasType?(:BUG) || pbPartyHasType?(:STEEL)
      when :SWAMP # Swamp field
        fieldscore*=0.7 if attacker.pbHasMove?(:SLEEPPOWDER)
        fieldscore*=1.3 if checkAImoves([:SLEEPPOWDER],aimem)
      when :RAINBOW # Rainbow field
        fieldscore*=1.5 if opponent.hasType?(:NORMAL) || opponent.pbPartner.hasType?(:NORMAL)
        fieldscore*=0.5 if attacker.hasType?(:NORMAL)
        fieldscore*=0.5 if pbPartyHasType?(:NORMAL)
        fieldscore*=1.4 if opponent.ability == :CLOUDNINE
        fieldscore*=0.6 if attacker.ability == :CLOUDNINE
        fieldscore*=0.8 if attacker.pbHasMove?(:SONICBOOM)
        fieldscore*=1.2 if checkAImoves([:SONICBOOM],aimem)
      when :CORROSIVE # Corrosive field
        fieldscore*=1.3 if opponent.hasType?(:POISON) || opponent.pbPartner.hasType?(:POISON)
        fieldscore*=0.7 if attacker.hasType?(:POISON)
        fieldscore*=0.7 if pbPartyHasType?(:POISON)
        fieldscore*=1.5 if opponent.ability == :CORROSION
        fieldscore*=0.5 if attacker.ability == :CORROSION
        fieldscore*=0.7 if attacker.pbHasMove?(:SLEEPPOWDER)
        fieldscore*=1.3 if checkAImoves([:SLEEPPOWDER],aimem)
      when :CORROSIVEMIST # Corromist field
        if violent
          if !PBStuff::INVULEFFECTS.any? {|eff| opponent.effects[eff] } && !(PBStuff::TWOTURNMOVE.include?(opponent.effects[:TwoTurnAttack]) && pbAIfaster?(nil,nil,attacker,opponent)) && opponent.ability != :FLASHFIRE
            fieldscore*=2 if (attacker.hp.to_f)/attacker.totalhp<0.2
            fieldscore*=5 if opponent.pbNonActivePokemonCount==0
          end
        end
        fieldscore*=1.3 if opponent.hasType?(:POISON) || opponent.pbPartner.hasType?(:POISON)
        if attacker.hasType?(:POISON)
          fieldscore*=0.7
        elsif !attacker.hasType?(:STEEL)
          fieldscore*=1.4
        end
        fieldscore*=1.4 if !pbPartyHasType?(:POISON)
        fieldscore*=1.5 if opponent.ability == :CORROSION
        fieldscore*=0.5 if attacker.ability == :CORROSION
        fieldscore*=1.5 if opponent.hasType?(:FIRE) || opponent.pbPartner.hasType?(:FIRE)
        fieldscore*=0.8  if attacker.hasType?(:FIRE)
        fieldscore*=0.8  if pbPartyHasType?(:FIRE)
      when :DESERT # Desert field
        fieldscore*=1.3 if attacker.spatk > attacker.attack && (opponent.hasType?(:GROUND) || opponent.pbPartner.hasType?(:GROUND))
        fieldscore*=0.7 if opponent.spatk > opponent.attack && (attacker.hasType?(:GROUND))
        fieldscore*=1.5 if attacker.hasType?(:ELECTRIC) || attacker.hasType?(:WATER)
        fieldscore*=0.5 if opponent.hasType?(:ELECTRIC) || opponent.pbPartner.hasType?(:WATER)
        fieldscore*=0.7 if pbPartyHasType?(:GROUND)
        fieldscore*=1.5 if pbPartyHasType?(:WATER) || pbPartyHasType?(:ELECTRIC)
        fieldscore*=1.3 if opponent.ability == :SANDRUSH && @battle.pbWeather!=:SANDSTORM
        fieldscore*=0.7 if attacker.ability == :SANDRUSH && @battle.pbWeather!=:SANDSTORM
      when :ICY # Icy field
        fieldscore*=1.3 if opponent.hasType?(:ICE) || opponent.pbPartner.hasType?(:ICE)
        fieldscore*=0.5 if attacker.hasType?(:ICE)
        fieldscore*=0.5 if pbPartyHasType?(:ICE)
        fieldscore*=0.5 if opponent.hasType?(:FIRE) || opponent.pbPartner.hasType?(:FIRE)
        fieldscore*=1.1 if attacker.hasType?(:FIRE)
        fieldscore*=1.1 if pbPartyHasType?(:FIRE)
        fieldscore*=1.3 if (opponent.ability == :SLUSHRUSH || opponent.crested == :EMPOLEON || (opponent.crested == :CASTFORM && opponent.form == 3)) && @battle.pbWeather!=:HAIL
        fieldscore*=0.7 if (attacker.ability == :SLUSHRUSH || attacker.crested == :EMPOLEON || (attacker.crested == :CASTFORM && attacker.form == 3)) && @battle.pbWeather!=:HAIL
      when :ROCKY # Rocky field
        fieldscore*=1.5 if opponent.hasType?(:ROCK) || opponent.pbPartner.hasType?(:ROCK)
        fieldscore*=0.5 if attacker.hasType?(:ROCK)
        fieldscore*=0.5 if pbPartyHasType?(:ROCK)
      when :FOREST # Forest field
        fieldscore*=1.5 if opponent.hasType?(:GRASS) || opponent.hasType?(:BUG) || opponent.pbPartner.hasType?(:GRASS) || opponent.pbPartner.hasType?(:BUG)
        fieldscore*=0.5 if attacker.hasType?(:GRASS) || attacker.hasType?(:BUG)
        fieldscore*=0.5 if pbPartyHasType?(:GRASS) || pbPartyHasType?(:BUG)
        fieldscore*=1.8 if opponent.hasType?(:FIRE) || opponent.pbPartner.hasType?(:FIRE)
        fieldscore*=0.2 if attacker.hasType?(:FIRE)
        fieldscore*=0.2 if pbPartyHasType?(:FIRE)
      when :SUPERHEATED # Superheated field
        fieldscore*=1.8 if opponent.hasType?(:FIRE) || opponent.pbPartner.hasType?(:FIRE)
        fieldscore*=0.2 if attacker.hasType?(:FIRE)
        fieldscore*=0.2 if pbPartyHasType?(:FIRE)
        fieldscore*=0.7 if opponent.hasType?(:ICE) || opponent.pbPartner.hasType?(:ICE)
        fieldscore*=1.5 if attacker.hasType?(:ICE)
        fieldscore*=1.5 if pbPartyHasType?(:ICE)
        fieldscore*=0.8 if opponent.hasType?(:WATER) || opponent.pbPartner.hasType?(:WATER)
        fieldscore*=1.2 if attacker.hasType?(:WATER)
        fieldscore*=1.2 if pbPartyHasType?(:WATER)
      when :FACTORY # Factory field
        fieldscore*=1.2 if opponent.hasType?(:ELECTRIC) || opponent.pbPartner.hasType?(:ELECTRIC)
        fieldscore*=0.8 if attacker.hasType?(:ELECTRIC)
        fieldscore*=0.8 if pbPartyHasType?(:ELECTRIC)
      when :SHORTCIRCUIT # Short-Circuit field
        fieldscore*=1.4 if opponent.hasType?(:ELECTRIC) || opponent.pbPartner.hasType?(:ELECTRIC)
        fieldscore*=0.6 if attacker.hasType?(:ELECTRIC)
        fieldscore*=0.6 if pbPartyHasType?(:ELECTRIC)
        fieldscore*=1.3 if opponent.ability == :SURGESURFER
        fieldscore*=0.7 if attacker.ability == :SURGESURFER
        fieldscore*=1.3 if opponent.hasType?(:DARK) || opponent.pbPartner.hasType?(:DARK) || opponent.hasType?(:GHOST) || opponent.pbPartner.hasType?(:GHOST)
        fieldscore*=0.7 if attacker.hasType?(:DARK) || attacker.hasType?(:GHOST)
        fieldscore*=0.7 if pbPartyHasType?(:DARK) || pbPartyHasType?(:GHOST)
      when :WASTELAND # Wasteland field
        fieldscore*=1.3 if opponent.hasType?(:POISON) || opponent.pbPartner.hasType?(:POISON)
        fieldscore*=0.7 if attacker.hasType?(:POISON)
        fieldscore*=0.7 if pbPartyHasType?(:POISON)
      when :ASHENBEACH # Ashen Beach field
        fieldscore*=1.3 if opponent.hasType?(:FIGHTING) || opponent.pbPartner.hasType?(:FIGHTING) || opponent.hasType?(:PSYCHIC) || opponent.pbPartner.hasType?(:PSYCHIC)
        fieldscore*=0.7 if attacker.hasType?(:FIGHTING) || attacker.hasType?(:PSYCHIC)
        fieldscore*=0.7 if pbPartyHasType?(:FIGHTING) || pbPartyHasType?(:PSYCHIC)
        fieldscore*=1.3 if opponent.ability == :SANDRUSH && @battle.pbWeather!=:SANDSTORM
        fieldscore*=0.7 if attacker.ability == :SANDRUSH && @battle.pbWeather!=:SANDSTORM
      when :WATERSURFACE # Water Surface field
        fieldscore*=1.6 if opponent.hasType?(:WATER) || opponent.pbPartner.hasType?(:WATER)
        if attacker.hasType?(:WATER)
          fieldscore*=0.4
        elsif !attacker.isAirborne?
          fieldscore*=1.3
        end
        fieldscore*=0.4 if pbPartyHasType?(:WATER)
        fieldscore*=1.3 if opponent.ability == :SWIFTSWIM && @battle.pbWeather!=:RAINDANCE
        fieldscore*=0.7 if attacker.ability == :SWIFTSWIM && @battle.pbWeather!=:RAINDANCE
        fieldscore*=1.3 if opponent.ability == :SURGESURFER
        fieldscore*=0.7 if attacker.ability == :SURGESURFER
        fieldscore*=1.3 if !attacker.hasType?(:POISON) && @battle.field.counter==1
      when :UNDERWATER # Underwater field
        fieldscore*=2.0 if opponent.hasType?(:WATER) || opponent.pbPartner.hasType?(:WATER)
        if attacker.hasType?(:WATER)
          fieldscore*=0.1
        else
          fieldscore*=1.5
          fieldscore*=2 if attacker.hasType?(:ROCK) || attacker.hasType?(:GROUND)
        end
        fieldscore*=1.2 if attacker.attack > attacker.spatk
        fieldscore*=0.8 if opponent.attack > opponent.spatk
        fieldscore*=0.1 if pbPartyHasType?(:WATER)
        fieldscore*=0.9 if opponent.ability == :SWIFTSWIM
        fieldscore*=1.1 if attacker.ability == :SWIFTSWIM
        fieldscore*=1.1 if opponent.ability == :SURGESURFER
        fieldscore*=0.9 if attacker.ability == :SURGESURFER
        fieldscore*=1.3 if !attacker.hasType?(:POISON) && @battle.field.counter==1
      when :CAVE # Cave field
        fieldscore*=1.5 if opponent.hasType?(:ROCK) || opponent.pbPartner.hasType?(:ROCK)
        fieldscore*=0.5 if attacker.hasType?(:ROCK)
        fieldscore*=0.5 if pbPartyHasType?(:ROCK)
        fieldscore*=1.2 if opponent.hasType?(:GROUND) || opponent.pbPartner.hasType?(:GROUND)
        fieldscore*=0.8 if attacker.hasType?(:GROUND)
        fieldscore*=0.8 if pbPartyHasType?(:GROUND)
        fieldscore*=0.7 if opponent.hasType?(:FLYING) || opponent.pbPartner.hasType?(:FLYING)
        fieldscore*=1.3 if attacker.hasType?(:FLYING)
        fieldscore*=1.3 if pbPartyHasType?(:FLYING)
      when :GLITCH # Glitch field
        fieldscore*=1.3 if attacker.hasType?(:DARK) || attacker.hasType?(:STEEL) || attacker.hasType?(:FAIRY)
        fieldscore*=1.3 if pbPartyHasType?(:DARK) || pbPartyHasType?(:STEEL) || pbPartyHasType?(:FAIRY)
        ratio1 = attacker.spatk/attacker.spdef.to_f
        ratio2 = attacker.spdef/attacker.spatk.to_f
        if ratio1 < 1
          fieldscore*=ratio1
        elsif ratio2 < 1
          fieldscore*=ratio2
        end
        oratio1 = opponent.spatk/attacker.spdef.to_f
        oratio2 = opponent.spdef/attacker.spatk.to_f
        if oratio1 > 1
          fieldscore*=oratio1
        elsif oratio2 > 1
          fieldscore*=oratio2
        end
      when :CRYSTALCAVERN # Crystal Cavern field
        fieldscore*=1.5 if opponent.hasType?(:ROCK) || opponent.pbPartner.hasType?(:ROCK) || opponent.hasType?(:DRAGON) || opponent.pbPartner.hasType?(:DRAGON)
        fieldscore*=0.5 if attacker.hasType?(:ROCK) || attacker.hasType?(:DRAGON)
        fieldscore*=0.5 if pbPartyHasType?(:ROCK) || pbPartyHasType?(:DRAGON)
      when :MURKWATERSURFACE # Murkwater Surface field
        fieldscore*=1.6 if opponent.hasType?(:WATER) || opponent.pbPartner.hasType?(:WATER)
        if attacker.hasType?(:WATER)
          fieldscore*=0.4
        elsif !attacker.isAirborne?
          fieldscore*=1.3
        end
        fieldscore*=0.4 if pbPartyHasType?(:WATER)
        fieldscore*=1.3 if opponent.ability == :SWIFTSWIM && @battle.pbWeather!=:RAINDANCE
        fieldscore*=0.7 if attacker.ability == :SWIFTSWIM && @battle.pbWeather!=:RAINDANCE
        fieldscore*=1.3 if opponent.ability == :SURGESURFER
        fieldscore*=0.7 if attacker.ability == :SURGESURFER
        fieldscore*=1.3 if opponent.hasType?(:STEEL) || opponent.pbPartner.hasType?(:STEEL) || opponent.hasType?(:POISON) || opponent.pbPartner.hasType?(:POISON)
        if attacker.hasType?(:POISON)
          fieldscore*=0.7
        elsif !attacker.hasType?(:STEEL)
          fieldscore*=1.8
        end
        fieldscore*=0.7 if pbPartyHasType?(:POISON)
      when :MOUNTAIN # Mountain field
        fieldscore*=1.5 if opponent.hasType?(:ROCK) || opponent.pbPartner.hasType?(:ROCK) || opponent.hasType?(:FLYING) || opponent.pbPartner.hasType?(:FLYING)
        fieldscore*=0.5 if attacker.hasType?(:ROCK) || attacker.hasType?(:FLYING)
        fieldscore*=0.5 if pbPartyHasType?(:ROCK) || pbPartyHasType?(:FLYING)
      when :SNOWYMOUNTAIN # Snowy Mountain field
        fieldscore*=1.5 if opponent.hasType?(:ROCK) || opponent.pbPartner.hasType?(:ROCK) || opponent.hasType?(:FLYING) || opponent.pbPartner.hasType?(:FLYING) || opponent.hasType?(:ICE) || opponent.pbPartner.hasType?(:ICE)
        fieldscore*=0.5 if attacker.hasType?(:ROCK) || attacker.hasType?(:FLYING) || attacker.hasType?(:ICE)
        fieldscore*=0.5 if pbPartyHasType?(:ROCK) || pbPartyHasType?(:FLYING) || pbPartyHasType?(:ICE)
        fieldscore*=0.5 if opponent.hasType?(:FIRE) || opponent.pbPartner.hasType?(:FIRE)
        fieldscore*=1.5 if attacker.hasType?(:FIRE)
        fieldscore*=1.5 if pbPartyHasType?(:FIRE)
        fieldscore*=1.3 if (opponent.ability == :SLUSHRUSH || opponent.crested == :EMPOLEON || (opponent.crested == :CASTFORM && opponent.form == 3)) && @battle.pbWeather!=:HAIL
        fieldscore*=0.7 if (attacker.ability == :SLUSHRUSH || attacker.crested == :EMPOLEON || (attacker.crested == :CASTFORM && attacker.form == 3)) && @battle.pbWeather!=:HAIL
      when :HOLY # Holy field
        fieldscore*=1.4 if opponent.hasType?(:NORMAL) || opponent.pbPartner.hasType?(:NORMAL) || opponent.hasType?(:FAIRY) || opponent.pbPartner.hasType?(:FAIRY)
        fieldscore*=0.6 if attacker.hasType?(:NORMAL) || attacker.hasType?(:FAIRY)
        fieldscore*=0.6 if pbPartyHasType?(:NORMAL) || pbPartyHasType?(:FAIRY)
        fieldscore*=0.5 if opponent.hasType?(:DARK) || opponent.pbPartner.hasType?(:DARK) || opponent.hasType?(:GHOST) || opponent.pbPartner.hasType?(:GHOST)
        fieldscore*=1.5 if attacker.hasType?(:DARK) || attacker.hasType?(:GHOST)
        fieldscore*=1.5 if pbPartyHasType?(:DARK) || pbPartyHasType?(:GHOST)
        fieldscore*=1.2 if opponent.hasType?(:DRAGON) || opponent.pbPartner.hasType?(:DRAGON) || opponent.hasType?(:PSYCHIC) || opponent.pbPartner.hasType?(:PSYCHIC)
        fieldscore*=0.8 if attacker.hasType?(:DRAGON) || attacker.hasType?(:PSYCHIC)
        fieldscore*=0.8 if pbPartyHasType?(:DRAGON) || pbPartyHasType?(:PSYCHIC)
      when :MIRROR # Mirror field
        if violent
          if opponent.stages[PBStats::EVASION] > 0 || (@mondata.oppitemworks && opponent.item == :BRIGHTPOWDER) ||
            (@mondata.oppitemworks && opponent.item == :LAXINCENSE) || accuracyWeatherAbilityActive?(opponent)
            fieldscore*=1.3
          else
            fieldscore*=0.5
          end
        end
        fieldscore*=1+0.1*opponent.stages[PBStats::ACCURACY]
        fieldscore*=1+0.1*opponent.stages[PBStats::EVASION]
        fieldscore*=1-0.1*attacker.stages[PBStats::ACCURACY]
        fieldscore*=1-0.1*attacker.stages[PBStats::EVASION]
      when :FAIRYTALE # Fairytale field
        fieldscore*=1.5 if opponent.hasType?(:DRAGON) || opponent.pbPartner.hasType?(:DRAGON) || opponent.hasType?(:STEEL) || opponent.pbPartner.hasType?(:STEEL) || opponent.hasType?(:FAIRY) || opponent.pbPartner.hasType?(:FAIRY)
        fieldscore*=0.5 if attacker.hasType?(:DRAGON) || attacker.hasType?(:STEEL) || attacker.hasType?(:FAIRY)
        fieldscore*=0.5 if pbPartyHasType?(:DRAGON) || pbPartyHasType?(:STEEL) || pbPartyHasType?(:FAIRY)
        fieldscore*=1.3 if opponent.ability == :STANCECHANGE
        fieldscore*=0.7 if attacker.ability == :STANCECHANGE
      when :DRAGONSDEN # Dragon's Den field
        fieldscore*=1.7 if opponent.hasType?(:DRAGON) || opponent.pbPartner.hasType?(:DRAGON)
        fieldscore*=0.3 if attacker.hasType?(:DRAGON)
        fieldscore*=0.3 if pbPartyHasType?(:DRAGON)
        fieldscore*=1.5 if opponent.hasType?(:FIRE) || opponent.pbPartner.hasType?(:FIRE)
        fieldscore*=0.5 if attacker.hasType?(:FIRE)
        fieldscore*=0.5 if pbPartyHasType?(:FIRE)
        fieldscore*=1.3 if opponent.ability == :MULTISCALE
        fieldscore*=0.7 if attacker.ability == :MULTISCALE
      when :FLOWERGARDEN4 # Flower Garden field
        fieldscore*=1.5  if opponent.hasType?(:BUG) || opponent.pbPartner.hasType?(:BUG) || opponent.hasType?(:GRASS) || opponent.pbPartner.hasType?(:GRASS)
        fieldscore*=0.33 if attacker.hasType?(:GRASS) || attacker.hasType?(:BUG)
        fieldscore*=0.33 if pbPartyHasType?(:BUG) || pbPartyHasType?(:GRASS)
        fieldscore*=1.2  if opponent.hasType?(:FIRE) || opponent.pbPartner.hasType?(:FIRE)
        fieldscore*=0.33 if attacker.hasType?(:FIRE)
        fieldscore*=0.33 if pbPartyHasType?(:FIRE)
      when :FLOWERGARDEN5 # Flower Garden field
        fieldscore*=2.0  if opponent.hasType?(:BUG) || opponent.pbPartner.hasType?(:BUG) || opponent.hasType?(:GRASS) || opponent.pbPartner.hasType?(:GRASS)
        fieldscore*=0.25 if attacker.hasType?(:GRASS) || attacker.hasType?(:BUG)
        fieldscore*=0.25 if pbPartyHasType?(:BUG) || pbPartyHasType?(:GRASS)
        fieldscore*=1.6  if opponent.hasType?(:FIRE) || opponent.pbPartner.hasType?(:FIRE)
        fieldscore*=0.25 if attacker.hasType?(:FIRE)
        fieldscore*=0.25 if pbPartyHasType?(:FIRE)
      when :STARLIGHT # Starlight Arena field
        fieldscore*=1.5 if opponent.hasType?(:PSYCHIC) || opponent.pbPartner.hasType?(:PSYCHIC)
        fieldscore*=0.5 if attacker.hasType?(:PSYCHIC)
        fieldscore*=0.5 if pbPartyHasType?(:PSYCHIC)
        fieldscore*=1.3 if opponent.hasType?(:FAIRY) || opponent.pbPartner.hasType?(:FAIRY) || opponent.hasType?(:DARK) || opponent.pbPartner.hasType?(:DARK)
        fieldscore*=0.7 if attacker.hasType?(:FAIRY) || attacker.hasType?(:DARK)
        fieldscore*=0.7 if pbPartyHasType?(:FAIRY) || pbPartyHasType?(:DARK)
      when :NEWWORLD # New World field
        #fieldscore = 0
      when :INVERSE # Inverse field
        fieldscore*=1.7 if opponent.hasType?(:NORMAL) || opponent.pbPartner.hasType?(:NORMAL)
        fieldscore*=0.3 if attacker.hasType?(:NORMAL)
        fieldscore*=0.3 if pbPartyHasType?(:NORMAL)
        fieldscore*=1.5 if opponent.hasType?(:ICE) || opponent.pbPartner.hasType?(:ICE)
        fieldscore*=0.5 if attacker.hasType?(:ICE)
        fieldscore*=0.5 if pbPartyHasType?(:ICE)
      when :PSYTERRAIN # Psychic Terrain
        fieldscore*=1.7 if opponent.hasType?(:PSYCHIC) || opponent.pbPartner.hasType?(:PSYCHIC)
        fieldscore*=0.3 if attacker.hasType?(:PSYCHIC)
        fieldscore*=0.3 if pbPartyHasType?(:PSYCHIC)
        fieldscore*=1.3 if opponent.ability == :TELEPATHY
        fieldscore*=0.7 if attacker.ability == :TELEPATHY
    end
    fieldscore*=0.01
    return fieldscore
  end

################################################################################
# Item score functions
################################################################################

  def getItemScore
    #check if we have items
    @mondata.itemscore = {}
    return if !@battle.internalbattle
    return if @attacker.effects[:Embargo]>0
    return if @attacker.pbOwnSide.effects[:EmbargoSide]>0
    items = @battle.pbGetOwnerItems(@index)
    return if !items || items.empty?
    party = @battle.pbPartySingleOwner(@attacker.index)
    opponent1 = @attacker.pbOppositeOpposing
    return if @attacker.isFainted?
    movecount = -1
    maxplaypri = -1
    partynumber = 0
    aimem = getAIMemory(opponent1)
    for i in party
      next if i.nil?
      next if i.hp == 0
      partynumber+=1
    end
    # highest score
    for i in 0...@attacker.moves.length
      next if @attacker.moves[i].nil?

      if @mondata.roughdamagearray.transpose[i].max >= 100 && @attacker.moves[i] && @attacker.moves[i].priority > maxplaypri
        maxplaypri = @attacker.moves[i].priority
      end
    end
    highscore = @mondata.roughdamagearray.max { |a, b| a.max <=> b.max }.max
    highdamage = -1
    maxopppri = -1
    pridam = -1
    bestid = -1
    # expected damage
    for i in aimem
      tempdam = pbRoughDamage(i,opponent1,@attacker)
      if tempdam>highdamage
        highdamage = tempdam
        bestid = i.move
      end
      if i.priority > maxopppri
        maxopppri = i.priority
        pridam = tempdam
      end
    end
    highdamage = checkAIdamage()
    highratio = -1
    #expected damage percentage
    highratio = highdamage*(1.0/@attacker.hp) if @attacker.hp!=0
    PBDebug.log(sprintf("Beginning AI Item use check.\n")) if $INTERNAL
    for i in items
      next @mondata.itemscore[i] = -100000 if $cache.items[i].checkFlag?(:noUseInBattle)
      next @mondata.itemscore[i] = -8000 if $game_switches[:Stop_Items_Password] || $game_switches[:No_Items_Password] || KAIZOMOD
      next if @mondata.itemscore.key?(i)
      itemscore=100
      if PBStuff::HPITEMS.include?(i)
        PBDebug.log(sprintf("This is a HP-healing item.")) if $INTERNAL
        restoreamount=0
        case i
          when  :POTION     then restoreamount=20
          when  :ULTRAPOTION   then restoreamount=200
          when  :SUPERPOTION   then restoreamount=60
          when  :HYPERPOTION   then restoreamount=120
          when  :MAXPOTION, :FULLRESTORE then restoreamount=@attacker.totalhp
          when  :FRESHWATER   then restoreamount=30
          when  :SODAPOP     then restoreamount=50
          when  :LEMONADE   then restoreamount=70
          when  :MOOMOOMILK   then restoreamount=100
          when  :BUBBLETEA   then restoreamount=180
          when  :MEMEONADE   then restoreamount=103
          when  :STRAWBIC   then restoreamount=90
          when  :CHOCOLATEIC   then restoreamount=70
          when  :BLUEMIC     then restoreamount=200
        end
        resratio=restoreamount*(1.0/@attacker.totalhp)
        itemscore*= (2 - (2.0*@attacker.hp/@attacker.totalhp))
        if highdamage > (@attacker.totalhp - @attacker.hp) # if we take more damage from full than we currently have, don't bother
          itemscore*= 0
        elsif ([@attacker.hp+restoreamount,@attacker.totalhp].min - highdamage) < ((@attacker.totalhp / 4.0) + attacker.hp) # and if we're not gaining at least 25% hp, don't bother
          itemscore*= 0.3
        end
        if highdamage>=@attacker.hp
          if highdamage > [@attacker.hp+restoreamount,@attacker.totalhp].min
            itemscore*=0
          else
            itemscore*=1.2
          end
          if @attacker.moves.any? {|moveloop| !moveloop.zmove && moveloop.isHealingMove? && moveloop.move != :WISH}
            if !pbAIfaster?(nil,nil,@attacker, opponent1)
              if highdamage>=@attacker.hp
                itemscore*=1.1
              else
                itemscore*=0.6
                itemscore*=0.2 if resratio<0.55
              end
            end
          end
        else
          itemscore*=0.4
        end
        if highdamage > restoreamount
          itemscore*=0
        elsif restoreamount-highdamage < 15
          itemscore*=0.5
        end
        if pbAIfaster?(nil,nil,@attacker, opponent1)
          itemscore*=0.8
          if highscore >=110
            if maxopppri > maxplaypri
              itemscore*=1.3
              if pridam>@attacker.hp
                itemscore*= pridam>(@attacker.hp/2.0) ? 0 : 2
              end
            elsif !notOHKO?(@attacker, opponent1, true) && hpGainPerTurn >= 1
              itemscore*=0
            end
          end
          itemscore*=1.1 if @mondata.roles.include?(:SWEEPER)
        else
          if highdamage*2 > [@attacker.hp+restoreamount,@attacker.totalhp].min
            itemscore*=0
          else
            itemscore*=1.5
            itemscore*=1.5 if highscore >=110
          end
        end
        if @attacker.hp == @attacker.totalhp
          itemscore*=0
        elsif @attacker.hp >= (@attacker.totalhp*0.8)
          itemscore*=0.2
        elsif @attacker.hp >= (@attacker.totalhp*0.6)
          itemscore*=0.3
        elsif @attacker.hp >= (@attacker.totalhp*0.5)
          itemscore*=0.5
        end
        minipot = (partynumber-1)
        minimini = -1
        for j in items
          next if !PBStuff::HPITEMS.include?(j)
          minimini+=1
        end
        if minipot>minimini
          itemscore*=(0.9**(minipot-minimini))
          minipot=minimini
        elsif minimini>minipot
          itemscore*=(1.1**(minimini-minipot))
          minimini=minipot
        end
        itemscore*=0.6 if @mondata.roles.include?(:LEAD) || @mondata.roles.include?(:SCREENER)
        itemscore*=1.1 if @mondata.roles.include?(:TANK)
        itemscore*=1.1 if @mondata.roles.include?(:SECOND)
        itemscore*=0.9 if hpGainPerTurn>1
        itemscore*=1.3 if hpGainPerTurn<1
        if !@attacker.status.nil? && i != :FULLRESTORE
          itemscore*=0.7
          itemscore*=0.2 if @attacker.effects[:Toxic]>0 && partynumber>1
        end
        eff1 = PBTypes.twoTypeEff(opponent1.type1,@attacker.type1,@attacker.type2)
        itemscore*=0.7 if eff1>4
        itemscore*=1.1 if eff1<4
        itemscore*=1.2 if eff1==0
        eff2 = PBTypes.twoTypeEff(opponent1.type2,@attacker.type1,@attacker.type2)
        itemscore*=0.7 if eff2>4
        itemscore*=1.1 if eff2<4
        itemscore*=1.2 if eff2==0
        itemscore*=0.7 if @attacker.ability == :REGENERATOR && partynumber>1
        # Gen 9 Mod - Added Hospitality
        itemscore*=0.7 if @attacker.ability == :HOSPITALITY && partynumber>1 && @attacker.pbPartner
      end
      if PBStuff::STATUSITEMS.include?(i)
        PBDebug.log(sprintf("This is a status-curing item.")) if $INTERNAL
        if !(i== :FULLRESTORE)
          itemscore*=2 if highdamage < @attacker.hp / 2
          itemscore*=0 if @attacker.status.nil?
          if highdamage>@attacker.hp
            if (bestid==:WAKEUPSLAP && @attacker.status== :SLEEP) || (bestid==:SMELLINGSALTS && @attacker.status== :PARALYSIS) || bestid==:HEX
              itemscore*= highdamage*0.5 > @attacker.hp ? 0 : 1.4
            else
              itemscore*=0
            end
          end
          if @attacker.status== :SLEEP
            itemscore*=0.6 if @attacker.pbHasMove?(:SLEEPTALK) || @attacker.pbHasMove?(:SNORE) || @attacker.pbHasMove?(:REST) || @attacker.ability == :COMATOSE
            itemscore*=1.3 if checkAImoves([:DREAMEATER,:NIGHTMARE],aimem) || opponent1.ability == :BADDREAMS
            itemscore*= highdamage > 0.2 * @attacker.hp ? 1.3 : 0.7
          end
          if @attacker.status== :PARALYSIS
            itemscore*=0.5 if @attacker.ability == :QUICKFEET || @attacker.ability == :GUTS
            itemscore*=1.3 if @attacker.pbSpeed>opponent1.pbSpeed && (@attacker.pbSpeed*0.5)<opponent1.pbSpeed
            itemscore*=1.1
          end
          if @attacker.status== :BURN
            itemscore*=1.1
            itemscore*= @attacker.attack>@attacker.spatk ? 1.2 : 0.8
            itemscore*=0.6 if @attacker.ability == :GUTS
            itemscore*=0.7 if @attacker.ability == :MAGICGUARD
            itemscore*=0.7 if @attacker.ability == :WONDERGUARD && @battle.FE == :COLOSSEUM
            itemscore*=0.8 if @attacker.ability == :FLAREBOOST
          end
          if @attacker.status== :POISON
            itemscore*=1.1
            itemscore*=0.5 if @attacker.ability == :GUTS
            itemscore*=0.5 if @attacker.ability == :MAGICGUARD
            itemscore*=0.5 if @attacker.ability == :WONDERGUARD && @battle.FE == :COLOSSEUM
            itemscore*=0.5 if @attacker.ability == :TOXICBOOST
            itemscore*=0.2 if @attacker.ability == :POISONHEAL || @attacker.crested == :ZANGOOSE
            itemscore*=1.1 if @attacker.effects[:Toxic]>0
            itemscore*=1.5 if @attacker.effects[:Toxic]>3
          end
          if @attacker.status== :FROZEN
            if (KAIZOMOD)
              itemscore*=1.1
              itemscore*= @attacker.spatk>@attacker.attack ? 1.2 : 0.8
              itemscore*=0.6 if @attacker.ability == :GUTS
              itemscore*=0.7 if @attacker.ability == :MAGICGUARD
              itemscore*=0.7 if @attacker.ability == :WONDERGUARD && @battle.FE == :COLOSSEUM
            else
              itemscore*=1.3
              itemscore*=0.5 if @attacker.moves.any? {|moveloop| moveloop!=nil && moveloop.canThawUser?}
              itemscore*=  highdamage > 0.15 * @attacker.hp ? 1.1 : 0.9
            end
          end
        end
        itemscore*=0.5 if @attacker.pbHasMove?(:REFRESH) || @attacker.pbHasMove?(:REST) || @attacker.pbHasMove?(:PURIFY)
        itemscore*=0.2 if @attacker.ability == :NATURALCURE && partynumber>1
        itemscore*=0.3 if @attacker.ability == :SHEDSKIN

      end
      # General "Is it a good idea to use an item at all right now" checks
      if partynumber==1 || @mondata.roles.include?(:ACE)
        itemscore*=1.2
      else
        itemscore*=0.8
        itemscore*=0.6 if @attacker.itemUsed2
      end
      itemscore*=2 if @attacker.effects[:Toxic]>3 && i == :FULLRESTORE
      itemscore*=0.9 if @attacker.effects[:Confusion]>0
      itemscore*=0.6 if @attacker.effects[:Attract]>=0
      itemscore*=1.1 if @attacker.effects[:Substitute]>0
      itemscore*=0.5 if @attacker.effects[:LeechSeed]>=0
      itemscore*=0.5 if @attacker.effects[:Curse]
      # Gen 9 Mod - Item use disincentivized if attacker is being salt cured.
      itemscore*=0.7 if @attacker.effects[:SaltCure] && @attacker.ability != :MAGICGUARD
      itemscore*=0.7 if @attacker.effects[:SaltCure] && @attacker.ability != :MAGICGUARD && (@attacker.hasType?(:WATER) || @attacker.hasType?(:STEEL))
      itemscore*=0.2 if @attacker.effects[:PerishSong]>0
      minipot=0
      for s in [PBStats::ATTACK,PBStats::DEFENSE,PBStats::SPEED, PBStats::SPATK,PBStats::SPDEF,PBStats::ACCURACY,PBStats::EVASION]
        minipot+=@attacker.stages[s]
      end
      if @mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL)
        for s in [PBStats::DEFENSE,PBStats::SPDEF]
          minipot+=@attacker.stages[s]
        end
      end
      if @mondata.roles.include?(:SWEEPER)
        minipot+=@attacker.stages[PBStats::SPEED]
        minipot+= @attacker.attack>@attacker.spatk ? @attacker.stages[PBStats::ATTACK] : @attacker.stages[PBStats::SPATK]
      end


      itemscore*=0.05*minipot + 1
      itemscore*=1.2 if opponent1.effects[:TwoTurnAttack]!=0 || opponent1.effects[:HyperBeam]>0
      itemscore*= highscore>70 ? 1.1 : 0.9

      fielddisrupt = getFieldDisruptScore(@attacker,opponent1)
      fielddisrupt=0.6 if fielddisrupt <= 0
      itemscore*= (1.0/fielddisrupt)

      itemscore*=0.9 if @battle.trickroom > 0
      itemscore*=0.6 if @attacker.pbOwnSide.effects[:Tailwind]>0
      itemscore*=0.9 if @attacker.pbOwnSide.effects[:Reflect]>0
      itemscore*=0.9 if @attacker.pbOwnSide.effects[:LightScreen]>0
      itemscore*=0.8 if @attacker.pbOwnSide.effects[:AuroraVeil]>0
      itemscore*=0.8 if @battle.doublebattle
      itemscore*=0.3 if @attacker.effects[:Rollout] > 0
      itemscore-=100
      PBDebug.log(sprintf("Score for %s: %d",getItemName(i),itemscore)) if $INTERNAL && !i.nil?
      $ai_log_data[@attacker.index].items.push(getItemName(i))
      $ai_log_data[@attacker.index].items_scores.push(itemscore)
      @mondata.itemscore[i] = itemscore
    end
    #somehow register that this would be the item that should be used
    PBDebug.log(sprintf("Highest item score: %d",(@mondata.itemscore.values.max))) if $INTERNAL
    #score the item if we have it
  end


################################################################################
# Switching functions
################################################################################
  #function for getting the new switch-in when sending new mon out cuz fainted
  def pbDefaultChooseNewEnemy(index, party)
    # index is index of battler
    @mondata = @aimondata[index]
    @attacker = @battle.battlers[index]
    @index = index
    @opponent = illusionCheck(@attacker, firstOpponent()) ? firstOpponent().effects[:Illusion] : firstOpponent()
    switchscores = getSwitchInScoresParty(false)
    return switchscores.index(switchscores.max)
  end

  def getSwitchingScore
    #Set up some basic checks to prompt the remainder of the switch code
    #upon passing said checks:
    @mondata.shouldswitchscore = shouldSwitch?()
    $ai_log_data[@attacker.index].should_switch_score = @mondata.shouldswitchscore
    PBDebug.log(sprintf("ShouldSwitchScore: %d \n",@mondata.shouldswitchscore)) if $INTERNAL

    if @mondata.shouldswitchscore > 0
      @mondata.switchscore = getSwitchInScoresParty(true)
    end
  end

  def getSwitchInScoresParty(hard_switch, revival = false)
    party = revival ? @battle.pbParty(@attacker.index).find_all {|mon| mon && !mon.egg? && mon.hp  == 0} : @battle.pbParty(@attacker.index)
    if @mondata.skill < MEDIUMSKILL
      # Bad trainers likely don't know what a pikachu is, and just swap in random mons

      partyScores = Array.new(party.length, -10000000)
      # if there are no switch-ins at all
      return partyScores if hard_switch || !party.any? { |pkmn| @battle.pbCanSwitchLax?(@attacker.index, party.index(pkmn), false, revival) }

      ranvar = 0
      1000.times do
        ranvar = @battle.pbRandom(party.length)
        break if @battle.pbCanSwitchLax?(@attacker.index, ranvar, false)
      end
      partyScores[ranvar] = 100
      return partyScores
    end
    partyScores = []
    aimem = getAIMemory(@opponent)
    aimem2 = @opponent.pbPartner.hp > 0 ? getAIMemory(@opponent.pbPartner) : []

    # For checks at end for all pokemon
    survivors = Array.new(party.length, false)
    partycheck = []

    for partyindex in 0...party.length
      monscore = 0
      i = pbMakeFakeBattler(party[partyindex], partyindex) rescue nil
      nonmegaform = pbMakeFakeBattler(party[partyindex], partyindex) rescue nil
      if revival
        i.hp = [(i.totalhp / 2.0).floor, 1].max
        nonmegaform.hp = [(nonmegaform.totalhp / 2.0).floor, 1].max
      end
      @opponent = pbCloneBattler(firstOpponent().index, illusionCheck(firstOpponent(), @battle.battlers[firstOpponent().index]))
      if i.nil?
        partyScores.push(-10000000)
        PBDebug.log(sprintf("Score: -10000000\n")) if $INTERNAL
        $ai_log_data[@attacker.index].switch_scores.push(-10000000)
        $ai_log_data[@attacker.index].switch_name.push("")
        next
      end
      PBDebug.log(sprintf("Scoring for %s switching to: %s",getMonName(@attacker.species),getMonName(i.species))) if $INTERNAL
      if hard_switch
        if !@battle.pbCanSwitch?(@attacker.index,partyindex,false)
          partyScores.push(-10000000)
          PBDebug.log(sprintf("Score: -10000000\n")) if $INTERNAL
          $ai_log_data[@attacker.index].switch_scores.push(-10000000)
          $ai_log_data[@attacker.index].switch_name.push(getMonName(i.pokemon.species))
          next
        end
      else # not hard switch ergo dead mon
        if !@battle.pbCanSwitchLax?(@attacker.index, partyindex, false, revival)
          partyScores.push(-10000000)
          PBDebug.log(sprintf("Score: -10000000\n")) if $INTERNAL
          $ai_log_data[@attacker.index].switch_scores.push(-10000000)
          $ai_log_data[@attacker.index].switch_name.push(getMonName(i.pokemon.species))
          next
        end
      end
      if !i.moves.any? {|moveloop| moveloop != nil && moveloop.move != 0 && moveloop.move != :LUNARDANCE}
        partyScores.push(-1000)
        PBDebug.log(sprintf("Lunar mon sacrifice- Score: -1000\n")) if $INTERNAL
        $ai_log_data[@attacker.index].switch_scores.push(-1000)
        $ai_log_data[@attacker.index].switch_name.push(getMonName(i.pokemon.species))
        next
      end
      # Gen 9 Mod - Preserve a pokemon with Supreme Overlord for later.
      if i.ability == :SUPREMEOVERLORD
        partyScores.push(-4000)
        PBDebug.log(sprintf("Supreme Overlord later- Score: -5000\n")) if $INTERNAL
        $ai_log_data[@attacker.index].switch_scores.push(-5000)
        $ai_log_data[@attacker.index].switch_name.push(getMonName(i.pokemon.species))
        next
      end
      # Gen 9 Mod - Preserve a pokemon with Last Respects for later.
      if !i.moves.any? {|moveloop| moveloop != nil && moveloop.move != 0 && moveloop.move != :LASTRESPECTS}
        partyScores.push(-5000)
        PBDebug.log(sprintf("Last Respects later- Score: -5000\n")) if $INTERNAL
        $ai_log_data[@attacker.index].switch_scores.push(-5000)
        $ai_log_data[@attacker.index].switch_name.push(getMonName(i.pokemon.species))
        next
      end
      if partyindex == party.length-1 && $game_switches[:Last_Ace_Switch]
        partyScores.push(-10000)
        PBDebug.log(sprintf("Ace Switch Prevention- Score: -10000\n")) if $INTERNAL
        $ai_log_data[@attacker.index].switch_scores.push(-10000)
        $ai_log_data[@attacker.index].switch_name.push(getMonName(i.pokemon.species))
        next
      end
      theseRoles = @mondata.partyroles[partyindex%6] if @mondata.partyroles[partyindex%6]
      theseRoles = pbGetMonRoles(i) if !theseRoles
      if @battle.pbCanMegaEvolveAI?(i,@attacker.index)
        i.pokemon.makeMega
      end
      if @battle.pbCanGigaEvolveAI?(i,@attacker.index)
				i.pokemon.makeGiga
			end
      #speed changing
      pbStatChangingSwitch(i)
      pbStatChangingSwitch(nonmegaform)
      if i.ability == :MIMICRY
        type = :NORMAL
        type = @battle.field.mimicry
        i.type1=type
        i.type2=nil
      end
      if (i.ability == :IMPOSTER)
        transformed = true
        i = pbMakeFakeBattler(@opponent.pokemon, @opponent.pokemonIndex)
        i.hp = nonmegaform.hp
        i.item = nonmegaform.item

        monscore += 20*@opponent.stages[PBStats::ATTACK]
        monscore += 20*@opponent.stages[PBStats::SPATK]
        monscore += 20*@opponent.stages[PBStats::SPEED]
      end
      if Rejuv && @battle.FE == :INVERSE && i.item == :MAGICALSEED
        i.type1=:NORMAL
        i.type2=nil
        i.ability = :NORMALIZE
      end


      # Information gathering
      opp_best_move, incomingdamage = checkAIMovePlusDamage(@opponent, i)

      roughdamagearray = [[0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]] # Order: First Opp, Second Opp, Partner, Sum if multi-target
      for moveindex in 0...i.moves.length
        @move = i.moves[moveindex]
        next if @move.nil?

        roughdamagearray[0][moveindex] = [(pbRoughDamage(@move, i, @opponent) * 100) / (@opponent.hp.to_f), 100].min if @opponent.hp > 0
        if @battle.doublebattle
          roughdamagearray[1][moveindex] = [(pbRoughDamage(@move, i, @opponent.pbPartner) * 100) / (@opponent.pbPartner.hp.to_f), 100].min if @opponent.pbPartner.hp > 0
          next if i.pbTarget(@move) != :AllNonUsers && !PARTNERFUNCTIONS.include?(@move.function)

          roughdamagearray[2][moveindex] = [(pbRoughDamage(@move, i, @attacker.pbPartner) * 100) / (@attacker.pbPartner.hp.to_f), 100].min if @attacker.pbPartner.hp > 0
        end
        if i.pbTarget(@move) == :AllOpposing
          roughdamagearray[3][moveindex] = roughdamagearray[0][moveindex] + roughdamagearray[1][moveindex]
        elsif i.pbTarget(@move) == :AllNonUsers
          roughdamagearray[3][moveindex] = roughdamagearray[0][moveindex] + roughdamagearray[1][moveindex] - 2 * roughdamagearray[2][moveindex]
        elsif i.pbTarget(@move) == :RandomOpposing && @battle.doublebattle
          roughdamagearray[3][moveindex] = (roughdamagearray[3][moveindex] + roughdamagearray[3][moveindex]) / 2
        end
      end
      bestmoveindex = (roughdamagearray[0] + roughdamagearray[1]).index((roughdamagearray[0] + roughdamagearray[1]).max) % 4
      bestmove = i.moves[bestmoveindex]

      # Defensive
      defscore = 0
      incomingdamage = checkAIdamage(i,@opponent)
      incomingdamage2 = 0
      incomingdamage2 += checkAIdamage(i,@opponent.pbPartner) if @battle.doublebattle
      incomingpercentage = (incomingdamage + incomingdamage2) / i.hp.to_f
      maxsingulardamage = [incomingdamage2, incomingdamage].max / i.hp.to_f
      PBDebug.log(sprintf("incomingpercentage: %f",incomingpercentage)) if $INTERNAL
      if incomingpercentage > 1.0 && !canKillBeforeOpponentKills?(i,@opponent)
        defscore -= 150
      else
        survivors[partyindex]=true
      end
      defscore += 25 if incomingpercentage < 0.5
      defscore += 10 if maxsingulardamage < 0.45
      defscore += 10 if maxsingulardamage < 0.4
      defscore += 10 if maxsingulardamage < 0.35
      defscore += 20 if maxsingulardamage < 0.3
      defscore += 50 if 2*incomingpercentage + hpGainPerTurn-1 < 0.5
      defscore += 20 if maxsingulardamage < 0.2
      defscore += 30 if maxsingulardamage < 0.1
      defscore += 50 if 3*incomingpercentage + 2*(hpGainPerTurn-1) < 0.3

      #check if hard switch_in lives assumed move
      if hard_switch && !@battle.doublebattle && (maxsingulardamage < 1.0 || pbAIfaster?(nil,nil,@opponent,i))
        assumed_move = checkAIbestMove()
        assumed_damage = pbRoughDamage(assumed_move,@opponent,nonmegaform)
        assumed_percentage = assumed_damage / nonmegaform.hp
        defscore += 30 if assumed_damage < 0.5
        defscore += 50 if assumed_damage < 0.3
        defscore += 90 if assumed_damage < 0.1
      end
      defscore *= 2 if @opponent.effects[:Substitute] > 0

      monscore += defscore
      PBDebug.log(sprintf("Defensive: %d",defscore)) if $INTERNAL

      #Offensive
      offscore=0

      # check damage
      offscore += 30 if roughdamagearray[3].max > 180
      offscore += 50 if roughdamagearray[0].max >= 100 || roughdamagearray[1].max >= 100
      offscore += 10 if [roughdamagearray[0].max, roughdamagearray[1].max].max > 90
      offscore += 10 if [roughdamagearray[0].max, roughdamagearray[1].max].max > 80
      offscore += 10 if [roughdamagearray[0].max, roughdamagearray[1].max].max > 70
      offscore += 10 if [roughdamagearray[0].max, roughdamagearray[1].max].max > 60
      offscore += 50 if roughdamagearray[0].max >= 50 || roughdamagearray[1].max >= 50
      offscore += 50 if roughdamagearray[0].max >= 100 && roughdamagearray[1].max >= 100

      bestmoveindex = (roughdamagearray[0] + roughdamagearray[1]).index((roughdamagearray[0] + roughdamagearray[1]).max) % 4
      offscore *= pbAIfaster?(i.moves[bestmoveindex], opp_best_move, i, @opponent) ? 1.25 : 0.75


      monscore += offscore
      PBDebug.log(sprintf("Offensive: %d",offscore)) if $INTERNAL
      # Roles
      rolescore=0
      if @mondata.skill >= HIGHSKILL
        if theseRoles.include?(:SWEEPER)
          rolescore+= @attacker.pbNonActivePokemonCount<2 ? 60 : -50
          rolescore+=30 if i.attack >= i.spatk && (@opponent.defense<@opponent.spdef || @opponent.pbPartner.defense<@opponent.pbPartner.spdef)
          rolescore+=30 if i.spatk >= i.attack && (@opponent.spdef<@opponent.defense || @opponent.pbPartner.spdef<@opponent.pbPartner.defense)
          rolescore+= (-10)* statchangecounter(@opponent,1,7,-1)
          rolescore+= (-10)* statchangecounter(@opponent.pbPartner,1,7,-1)
          rolescore+=10 if pbAIfaster?(nil,nil,i,@opponent) && rolescore > 0
          rolescore*= pbAIfaster?(nil,nil,i,@opponent) && rolescore > 0 ? 1.5 : 0.5
          rolescore+=50 if @opponent.status== :SLEEP || (@opponent.status== :FROZEN && !KAIZOMOD)
          rolescore+=50 if @opponent.pbPartner.status== :SLEEP || (@opponent.pbPartner.status== :FROZEN && !KAIZOMOD)
          # Gen 9 Mod - Last Respects / Supreme Overlord Pokemon aren't ready to sweep if enough other party pokemon aren't fainted.
          rolescore+= (25*(@attacker.pbFaintedPokemonCount - 2)) if @attacker.ability == :SUPREMEOVERLORD
          rolescore+= (50*(@attacker.pbFaintedPokemonCount - 2)) if @attacker.pbHasMove?(:LASTRESPECTS)
        end
        if theseRoles.include?(:PHYSICALWALL) || theseRoles.include?(:SPECIALWALL)
          rolescore+=30 if theseRoles.include?(:PHYSICALWALL) && (@opponent.spatk>@opponent.attack || @opponent.pbPartner.spatk>@opponent.pbPartner.attack)
          rolescore+=30 if theseRoles.include?(:SPECIALWALL) && (@opponent.spatk<@opponent.attack || @opponent.pbPartner.spatk<@opponent.pbPartner.attack)
          rolescore+=30 if @opponent.status== :BURN || @opponent.status== :POISON || @opponent.effects[:LeechSeed]>0
          rolescore+=30 if @opponent.pbPartner.status== :BURN || @opponent.pbPartner.status== :POISON || @opponent.pbPartner.effects[:LeechSeed]>0
        end
        if theseRoles.include?(:TANK)
          rolescore+=40 if @opponent.status== :PARALYSIS || @opponent.effects[:LeechSeed]>0
          rolescore+=40 if @opponent.pbPartner.status== :PARALYSIS || @opponent.pbPartner.effects[:LeechSeed]>0
          rolescore+=30 if @attacker.pbOwnSide.effects[:Tailwind]>0
        end
        if theseRoles.include?(:LEAD)
          rolescore+=10
          rolescore+=20 if (party.length - @attacker.pbNonActivePokemonCount) <= (party.length / 2).ceil
        end
        if @attacker.effects[:LunarDance] && (@battle.FE == :NEWWORLD || @battle.FE == :DANCEFLOOR)
          rolescore -= 100 if @attacker.pbNonActivePokemonCount > 2 # this might still need to be adjusted
          rolescore += 200 if @attacker.pbNonActivePokemonCount == 1
        end
        if theseRoles.include?(:CLERIC)
          partymidhp = false
          for k in party
            next if k.nil? || k==i || k.totalhp==0
            rolescore+=50 if !k.status.nil?
            partymidhp = true if 0.3<((k.hp.to_f)/k.totalhp) && ((k.hp.to_f)/k.totalhp)<0.6
          end
          rolescore+=50 if partymidhp
        end
        #now only does for lowered stats, but would also be very good for raised stats right?
        #evasion / accuracy doesn't make sense to me
        if theseRoles.include?(:PHAZER)
          for opp in [@opponent, @opponent.pbPartner]
            next if opp.hp <=0
            rolescore+= (10)*opp.stages[PBStats::ATTACK]  if opp.stages[PBStats::ATTACK]<0
            rolescore+= (20)*opp.stages[PBStats::DEFENSE]  if opp.stages[PBStats::DEFENSE]<0
            rolescore+= (10)*opp.stages[PBStats::SPATK]    if opp.stages[PBStats::SPATK]<0
            rolescore+= (20)*opp.stages[PBStats::SPDEF]    if opp.stages[PBStats::SPDEF]<0
            rolescore+= (10)*opp.stages[PBStats::SPEED]    if opp.stages[PBStats::SPEED]<0
            rolescore+= (20)*opp.stages[PBStats::EVASION]  if opp.stages[PBStats::ACCURACY]<0
          end
        end
        rolescore+=60 if theseRoles.include?(:SCREENER)
        # This is role related because it's the replacement for revenge killer
        for moveindex in 0...i.moves.length
          next if i.moves[moveindex].nil?

          if pbAIfaster?(i.moves[moveindex], nil, i, @opponent)
            if roughdamagearray[0][moveindex] >= 100 || roughdamagearray[1][moveindex] >= 100
              rolescore += 110
              break
            end
          end
        end
        if theseRoles.include?(:SPINNER)
          if !@opponent.hasType?(:GHOST) && (@opponent.pbPartner.hp==0 || !@opponent.pbPartner.hasType?(:GHOST))
            rolescore+=20*@attacker.pbOwnSide.effects[:Spikes]
            rolescore+=20*@attacker.pbOwnSide.effects[:ToxicSpikes]
            rolescore+=30 if @attacker.pbOwnSide.effects[:StickyWeb]
            rolescore+=30 if @attacker.pbOwnSide.effects[:StealthRock]
          end
        end
        if theseRoles.include?(:PIVOT)
          rolescore+=40
        end
        if theseRoles.include?(:BATONPASSER)
          rolescore+=50
        end
        if theseRoles.include?(:STALLBREAKER)
          rolescore+=80 if checkAIhealing(aimem) || checkAIhealing(aimem2)
        end
        if theseRoles.include?(:STATUSABSORBER)
          for specificmemory in [aimem, aimem2]
            next if specificmemory.length == 0
            for j in specificmemory
              statusmove = PBStuff::BURNMOVE.include?(j.move) || PBStuff::PARAMOVE.include?(j.move) || PBStuff::SLEEPMOVE.include?(j.move) || PBStuff::SCREENMOVE.include?(j.move)
            end
          end
          rolescore+=70 if statusmove
        end
        if theseRoles.include?(:TRAPPER)
          rolescore+=30 if pbAIfaster?(nil,nil,i,@opponent) && @opponent.totalhp!=0 && (@opponent.hp.to_f)/@opponent.totalhp<0.6
        end
        if theseRoles.include?(:WEATHERSETTER)
          rolescore+=30
          # Gen 9 Mod - Added Orichalcum Pulse
          if (i.ability == :DROUGHT) || (nonmegaform.ability == :DROUGHT) || i.pbHasMove?(:SUNNYDAY || i.ability == :ORICHALCUMPULSE)
            rolescore+=60 if @battle.weather!=:SUNNYDAY
          elsif (i.ability == :DRIZZLE) || (nonmegaform.ability == :DRIZZLE) || i.pbHasMove?(:RAINDANCE)
            rolescore+=60 if @battle.weather!=:RAINDANCE
          elsif (i.ability == :SANDSTREAM) || (nonmegaform.ability == :SANDSTREAM) || (i.ability == :SANDSPIT) || (nonmegaform.ability == :SANDSPIT) || i.pbHasMove?(:SANDSTORM)
            rolescore+=60 if @battle.weather!=:SANDSTORM
          elsif (i.ability == :SNOWWARNING) || (nonmegaform.ability == :SNOWWARNING) || i.pbHasMove?(:HAIL)
            rolescore+=60 if @battle.weather!=:HAIL
          elsif (i.ability == :PRIMORDIALSEA) || (i.ability == :DESOLATELAND) || (i.ability == :DELTASTREAM) ||
            (nonmegaform.ability == :PRIMORDIALSEA) || (nonmegaform.ability == :DESOLATELAND) || (nonmegaform.ability == :DELTASTREAM)
            rolescore+=60
          end
        end
        # TODO: Add field setters Gen 9 - Mod
      end
      monscore += rolescore
      PBDebug.log(sprintf("Roles: %d",rolescore)) if $INTERNAL
      # Weather
      weatherscore=0
      case @battle.weather
        when :HAIL
          weatherscore+=25 if (i.ability == :MAGICGUARD) || (i.ability == :OVERCOAT) || i.hasType?(:ICE) || (i.ability == :WONDERGUARD && @battle.FE == :COLOSSEUM)
          weatherscore+=50 if (i.ability == :SNOWCLOAK) || (i.ability == :ICEBODY) || i.ability == :LUNARIDOL
          weatherscore+=80 if (i.ability == :SLUSHRUSH) || (i.item == :EMPCREST && i.species == :EMPOLEON)
          weatherscore+=30 if (i.ability == :ICEFACE) && i.form == 1
        when :RAINDANCE
          weatherscore+=50 if (i.ability == :DRYSKIN) || (i.ability == :HYDRATION) || (i.ability == :RAINDISH)
          weatherscore+=80 if (i.ability == :SWIFTSWIM)
        when :SUNNYDAY
          weatherscore-=40 if (i.ability == :DRYSKIN)
          weatherscore+=50 if (i.ability == :SOLARPOWER) || (i.ability == :SOLARIDOL)
          weatherscore+=80 if (i.ability == :CHLOROPHYLL)
          # Gen 9 Mod - Added Protosynthesis & Orichalcum Pulse
          weatherscore+=80 if (i.ability == :PROTOSYNTHESIS) || (i.ability == :ORICHALCUMPULSE)
        when :SANDSTORM
          weatherscore+=25 if (i.ability == :MAGICGUARD) || (i.ability == :OVERCOAT) || i.hasType?(:ROCK) || i.hasType?(:GROUND) || i.hasType?(:STEEL) || (i.ability == :WONDERGUARD && @battle.FE == :COLOSSEUM)
          weatherscore+=50 if (i.ability == :SANDVEIL) || (i.ability == :SANDFORCE)
          weatherscore+=80 if (i.ability == :SANDRUSH)
      end
      if @battle.trickroom>0
        weatherscore+= i.pbSpeed<@opponent.pbSpeed ? 50 : -50
        weatherscore+= i.pbSpeed<@opponent.pbPartner.pbSpeed ? 50 : -50 if @opponent.pbPartner.hp > 0
      end
      monscore += weatherscore
      PBDebug.log(sprintf("Weather: %d",weatherscore)) if $INTERNAL
      #Moves
      movesscore=0
      if @mondata.skill>=HIGHSKILL
        if @attacker.pbOwnSide.effects[:ToxicSpikes] > 0
          movesscore+=80 if nonmegaform.hasType?(:POISON) && !nonmegaform.hasType?(:FLYING) && ![:LEVITATE,:SOLARDIOL,:LUNARIDOL].include?(nonmegaform.ability)
          movesscore+=30 if nonmegaform.hasType?(:FLYING) || nonmegaform.hasType?(:STEEL) || [:LEVITATE,:SOLARDIOL,:LUNARIDOL].include?(nonmegaform.ability)
        end
        if i.pbHasMove?(:CLEARSMOG) || i.pbHasMove?(:HAZE)
          movesscore+= (10)* statchangecounter(@opponent,1,7,1)
          movesscore+= (10)* statchangecounter(@opponent.pbPartner,1,7,1)
        end
        movesscore+=25 if i.pbHasMove?(:FAKEOUT) || i.pbHasMove?(:FIRSTIMPRESSION)
        if @attacker.pbPartner.totalhp != 0
          movesscore+=70 if i.pbHasMove?(:FUSIONBOLT) && @attacker.pbPartner.pbHasMove?(:FUSIONFLARE)
          movesscore+=70 if i.pbHasMove?(:FUSIONFLARE) && @attacker.pbPartner.pbHasMove?(:FUSIONBOLT)
        end
        movesscore+=30 if i.pbHasMove?(:RETALIATE) && @attacker.pbOwnSide.effects[:Retaliate]
        if i.pbHasMove?(:FELLSTINGER)
          movesscore+=50 if pbAIfaster?(nil,nil,i,@opponent) && (@opponent.hp.to_f)/@opponent.totalhp<0.2
          movesscore+=50 if pbAIfaster?(nil,nil,i,@opponent.pbPartner) && (@opponent.pbPartner.hp.to_f)/@opponent.pbPartner.totalhp<0.2
        end
        if i.pbHasMove?(:TAILWIND)
          movesscore+= @attacker.pbOwnSide.effects[:Tailwind]>0 ? -60 : 30
        end
        if i.pbHasMove?(:PURSUIT) || (i.pbHasMove?(:SANDSTORM) || i.pbHasMove?(:HAIL)) && @opponent.item != :SAFETYGOGGLES ||
           i.pbHasMove?(:TOXIC) || i.pbHasMove?(:LEECHSEED)
          movesscore+=150 if (@opponent.ability == :WONDERGUARD)
          movesscore+=150 if (@opponent.pbPartner.ability == :WONDERGUARD)
        end
      end
      monscore+=movesscore
      PBDebug.log(sprintf("Moves: %d",movesscore)) if $INTERNAL
      #Abilities
      abilityscore=0
      if @mondata.skill >= HIGHSKILL
        case i.ability
          when :DISGUISE
            if i.effects[:Disguise]
              abilityscore += 10 * statchangecounter(@opponent, 1, 7, 1)
              abilityscore += 10 * statchangecounter(@opponent.pbPartner, 1, 7, 1)
              abilityscore += 50 if roughdamagearray[0].max >= 100 || roughdamagearray[1].max >= 100
            end
          when :ICEFACE
            if i.effects[:IceFace] && (@opponent.attack > @opponent.spatk || @battle.FE == :FROZENDIMENSION)
              abilityscore += 10 * statchangecounter(@opponent, 1, 7, 1)
              abilityscore += 10 * statchangecounter(@opponent.pbPartner, 1, 7, 1)
              abilityscore += 50 if roughdamagearray[0].max >= 100 || roughdamagearray[1].max >= 100
            end
          when :UNAWARE
            abilityscore += 10 * statchangecounter(@opponent, 1, 7, 1)
            abilityscore += 10 * statchangecounter(@opponent.pbPartner, 1, 7, 1)
          when :DROUGHT, :DESOLATELAND
            abilityscore += 40 if @opponent.hasType?(:WATER)
            abilityscore += 40 if @opponent.pbPartner.hasType?(:WATER)
            for specificmemory in [aimem, aimem2]
              abilityscore += 15 if specificmemory.any? { |moveloop| moveloop != nil && moveloop.pbType(specificmemory == aimem ? @opponent : @opponent.pbPartner) == :WATER }
            end
          when :DRIZZLE, :PRIMORDIALSEA
            abilityscore += 40 if @opponent.hasType?(:FIRE)
            abilityscore += 40 if @opponent.pbPartner.hasType?(:FIRE)
            for specificmemory in [aimem, aimem2]
              abilityscore += 15 if specificmemory.any? { |moveloop| moveloop != nil && moveloop.pbType(specificmemory == aimem ? @opponent : @opponent.pbPartner) == :FIRE }
            end
          when :LIMBER
            abilityscore += 15 if checkAImoves(PBStuff::PARAMOVE, aimem)
            abilityscore += 15 if checkAImoves(PBStuff::PARAMOVE, aimem2)
          when :OBLIVIOUS
            abilityscore += 20 if @opponent.ability == :CUTECHARM || @opponent.pbPartner.ability == :CUTECHARM
            abilityscore += 20 if checkAImoves([:ATTRACT], aimem)
            abilityscore += 20 if checkAImoves([:ATTRACT], aimem2)
          when :COMPOUNDEYES
            abilityscore += 25 if @opponent.item == :LAXINCENSE || @opponent.item == :BRIGHTPOWDER || @opponent.stages[PBStats::EVASION] > 0 || accuracyWeatherAbilityActive?(@opponent)
            abilityscore += 25 if @opponent.pbPartner.item == :LAXINCENSE || @opponent.pbPartner.item == :BRIGHTPOWDER || @opponent.pbPartner.stages[PBStats::EVASION] > 0 || accuracyWeatherAbilityActive?(@opponent.pbPartner)
          when :COMATOSE
            abilityscore += 20 if checkAImoves(PBStuff::BURNMOVE, aimem)
            abilityscore += 20 if checkAImoves(PBStuff::PARAMOVE, aimem)
            abilityscore += 20 if checkAImoves(PBStuff::SLEEPMOVE, aimem)
            abilityscore += 20 if checkAImoves(PBStuff::POISONMOVE, aimem)
          when :INSOMNIA, :VITALSPIRIT
            abilityscore += 20 if checkAImoves(PBStuff::SLEEPMOVE, aimem)
          when :POISONHEAL, :TOXICBOOST, :IMMUNITY
            abilityscore += 20 if checkAImoves(PBStuff::POISONMOVE, aimem)
          when :MAGICGUARD
            abilityscore += 20 if checkAImoves([:LEECHSEED], aimem)
            abilityscore += 20 if checkAImoves([:WILLOWISP], aimem)
            abilityscore += 20 if checkAImoves(PBStuff::POISONMOVE, aimem)
          # Gen 9 Mod - Added Thermal Exchange
          when :WATERBUBBLE,:WATERVEIL,:FLAREBOOST,:THERMALEXCHANGE
            if checkAImoves(PBStuff::BURNMOVE,aimem)
              abilityscore += 10
              abilityscore += 10 if (i.ability == :FLAREBOOST)
            end
          # Gen 9 Mod - Added Purifying Salt
          when :PURIFYINGSALT
            abilityscore += 20 if checkAImoves(PBStuff::BURNMOVE,aimem)
            abilityscore += 20 if checkAImoves(PBStuff::PARAMOVE,aimem)
            abilityscore += 20 if checkAImoves(PBStuff::SLEEPMOVE,aimem)
            abilityscore += 20 if checkAImoves(PBStuff::POISONMOVE,aimem)
            abilityscore += 20 if checkAImoves(PBStuff::CONFUMOVE,aimem)
          when :OWNTEMPO
            abilityscore += 20 if checkAImoves(PBStuff::CONFUMOVE, aimem)
          when :SCREENCLEANER
            abilityscore += 10 if @opponent.pbOwnSide.effects[:Reflect] > 0
            abilityscore += 10 if @opponent.pbOwnSide.effects[:LightScreen] > 0
            abilityscore += 5 if @opponent.pbOwnSide.effects[:Safeguard] > 0
            abilityscore += 20 if @opponent.pbOwnSide.effects[:AuroraVeil] > 0
            abilityscore += 20 if @opponent.pbOwnSide.effects[:AreniteWall] > 0

            abilityscore -= 10 if @attacker.pbOwnSide.effects[:Reflect] > 0
            abilityscore -= 10 if @attacker.pbOwnSide.effects[:LightScreen] > 0
            abilityscore -= 5 if @attacker.pbOwnSide.effects[:Safeguard] > 0
            abilityscore -= 20 if @attacker.pbOwnSide.effects[:AuroraVeil] > 0
            abilityscore -= 20 if @attacker.pbOwnSide.effects[:AreniteWall] > 0
          when :CURIOUSMEDICINE
            abilityscore -= 10 * statchangecounter(@opponent, 1, 7, 1)
          when :COSTAR # Gen 9 Mod - Added Costar
            abilityscore += 10 * statchangecounter(@opponent, 1, 7, 1)
          when :INTIMIDATE, :FURCOAT, :STAMINA
            abilityscore += 40 if @opponent.attack > @opponent.spatk
            abilityscore += 40 if @opponent.pbPartner.attack > @opponent.pbPartner.spatk
          when :PRESSURE
            abilityscore += 40
            roles = pbGetMonRoles(@opponent)
            abilityscore += 10 if roles.include?(:PHYSICALWALL) || roles.include?(:SPECIALWALL)
            partner = @opponent.pbPartner
            roles = pbGetMonRoles(@partner)
            abilityscore += 40 if !partner.isFainted?
            abilityscore += 10 if roles.include?(:PHYSICALWALL) || roles.include?(:SPECIALWALL)
          when :UNNERVE
            abilityscore += 40
            abilityscore += 10 if pbGetMonRoles(@opponent).include?(:SWEEPER)
            abilityscore += 40 if !@opponent.pbPartner.isFainted?
            abilityscore += 10 if pbGetMonRoles(@opponent.pbPartner).include?(:SWEEPER)
          when :WONDERGUARD
            dievar = false
            instantdievar = false
            for j in aimem
              dievar = true if [:FIRE, :GHOST, :DARK, :ROCK, :FLYING].include?(j.pbType(@opponent))
            end
            if @mondata.skill >= BESTSKILL
              for j in aimem2
                dievar = true if [:FIRE, :GHOST, :DARK, :ROCK, :FLYING].include?(j.pbType(@opponent.pbPartner))
               end
            end
            if @battle.weather == :HAIL || @battle.weather == :SANDSTORM || @battle.weather == :SHADOWSKY
              dievar = true
              instantdievar = true
            end
            if i.status == :BURN || i.status == :POISON
              dievar = true
              instantdievar = true
            end
            if @attacker.pbOwnSide.effects[:StealthRock] || @attacker.pbOwnSide.effects[:Spikes] > 0 || @attacker.pbOwnSide.effects[:ToxicSpikes] > 0
              dievar = true
              instantdievar = true
            end
            dievar = true if moldBreakerCheck(@opponent)
            dievar = true if moldBreakerCheck(@opponent.pbPartner)
            abilityscore += 90 if !dievar
            abilityscore -= 90 if instantdievar
          # Gen 9 Mod - Added Lingering Aroma
          when :EFFECTSPORE, :STATIC, :POISONPOINT, :FLAMEBODY, :CUTECHARM, :MUMMY, :AFTERMATH, :GOOEY, :FLUFFY, :PERISHBODY, :WANDERINGSPIRIT, :LINGERINGAROMA
            if checkAIbestMove(@opponent).contactMove? || (@opponent.pbPartner.hp > 0 && checkAIbestMove(@opponent.pbPartner).contactMove?)
              abilityscore += 30 unless (i.ability == :FLUFFY && (@opponent.hasType?(:FIRE) || @opponent.pbPartner.hasType?(:FIRE))) || (i.ability == :PERISHBODY && @battle.FE == :HOLY)
            end
          when :IRONBARBS, :ROUGHSKIN
            if checkAIbestMove(@opponent).contactMove? || (@opponent.pbPartner.hp > 0 && checkAIbestMove(@opponent.pbPartner).contactMove?)
              abilityscore += 30
            end
            abilityscore += 30 if @opponent.ability == :SKILLLINK || @opponent.ability == :TECHLINK
            abilityscore += 30 if @opponent.pbPartner.hp > 0 && (@opponent.pbPartner.ability == :SKILLLINK || @opponent.pbPartner.ability == :TECHLINK)
            # Gen 9 Mod - Added Loaded Dice
            abilityscore += 30 if (@opponent.item == :LOADEDDICE)
            abilityscore += 30 if (@opponent.pbPartner.item == :LOADEDDICE)
          when :COTTONDOWN
            if incomingpercentage<0.5
              if roughdamagearray[0].max >= 60
                abilityscore+=50
              else
                abilityscore+=30
              end
            end
          when :TRACE
            # Gen 9 Mod - Added Earth Eater, Well-Baked Body, Wind Rider
            if ([:WATERABSORB,:VOLTABSORB,:STORMDRAIN,:MOTORDRIVE,:FLASHFIRE,:LEVITATE,:LUNARIDOL,:SOLARIDOL,:LIGHTNINGROD,
              :SAPSIPPER,:DRYSKIN,:SLUSHRUSH,:SANDRUSH,:SWIFTSWIM,:CHLOROPHYLL,:SPEEDBOOST,
              :WONDERGUARD,:PRANKSTER, :EARTHEATER, :WELLBAKEDBODY, :WINDRIDER].include?(@opponent.ability) ||
              (pbAIfaster?() && ((@opponent.ability == :ADAPTABILITY) || (@opponent.ability == :DOWNLOAD) || (@opponent.ability == :PROTEAN) || (@opponent.ability == :LIBERO))) ||
              (@opponent.attack>@opponent.spatk && (@opponent.ability == :INTIMIDATE)) || (@opponent.ability == :UNAWARE) || (i.hp==i.totalhp && ((@opponent.ability == :MULTISCALE) || (@opponent.ability == :SHADOWSHIELD)))) && i.item != :ABILITYSHIELD # Gen 9 Mod - Added Ability Shield
              abilityscore+=60
            end
          when :MAGMAARMOR
            abilityscore+=20 if aimem.any? {|moveloop| moveloop!=nil && moveloop.pbType(@opponent) == :ICE}
            abilityscore+=20 if aimem2.any? {|moveloop| moveloop!=nil && (@opponent.pbPartner.hp > 0 && moveloop.pbType(@opponent.pbPartner) == :ICE)}
          when :SOUNDPROOF
            abilityscore+=60 if checkAIbestMove(@opponent).isSoundBased? || (@opponent.pbPartner.hp>0 && checkAIbestMove(@opponent.pbPartner).isSoundBased?)
          when :THICKFAT
            abilityscore+=30 if (@opponent.pbPartner.hp > 0 && ([:ICE,:FIRE].include?(checkAIbestMove().pbType(@opponent)) || [:ICE,:FIRE].include?(checkAIbestMove(@opponent.pbPartner).pbType(@opponent.pbPartner))))
          when :WATERBUBBLE
            abilityscore+=30 if :FIRE ==checkAIbestMove().pbType(@opponent) || (@opponent.pbPartner.hp > 0 && :FIRE == checkAIbestMove(@opponent.pbPartner).pbType(@opponent.pbPartner))
          when :WELLBAKEDBODY # Gen 9 Mod - Added Well-Baked Body
            abilityscore+=60 if :FIRE ==checkAIbestMove().pbType(@opponent) || (@opponent.pbPartner.hp > 0 && :FIRE == checkAIbestMove(@opponent.pbPartner).pbType(@opponent.pbPartner))
          when :LIQUIDOOZE
            for j in aimem
              abilityscore+=40 if j.move==:LEECHSEED || j.function==0xDD || j.function==0x139 || j.function==0x158
            end
          when :RIVALRY
            abilityscore+=30 if i.gender==@opponent.gender && i.gender != 2 #nb
            abilityscore+=30 if (@opponent.pbPartner.hp > 0 && i.gender==@opponent.pbPartner.gender) && i.gender != 2
          when :SCRAPPY,:MINDSEYE # Gen 9 Mod - Added Mind's Eye
            abilityscore+=30 if @opponent.hasType?(:GHOST)
            abilityscore+=30 if (@opponent.pbPartner.hp > 0 && @opponent.pbPartner.hasType?(:GHOST))
          when :LIGHTMETAL
            abilityscore+=10 if checkAImoves([:GRASSKNOT,:LOWKICK],aimem)
            abilityscore+=10 if checkAImoves([:GRASSKNOT,:LOWKICK],aimem2) && @mondata.skill>=BESTSKILL
          when :ANALYTIC
            abilityscore+=30 if !pbAIfaster?(nil,nil,i,@opponent)
            abilityscore+=30 if (@opponent.pbPartner.hp > 0 && !pbAIfaster?(nil,nil,i,@opponent.pbPartner))
          when :ILLUSION
            abilityscore+=40
          when :MOXIE, :BEASTBOOST, :SOULHEART, :GRIMNEIGH, :CHILLINGNEIGH, :ASONECHILLING, :ASONEGRIM
            abilityscore += 40 if pbAIfaster?(nil, nil, i, @opponent) && ((@opponent.hp.to_f) / @opponent.totalhp < 0.5)
            abilityscore += 40 if (@opponent.pbPartner.hp > 0 && pbAIfaster?(nil, nil, i, @opponent.pbPartner) && ((@opponent.pbPartner.hp.to_f) / @opponent.pbPartner.totalhp < 0.5))
          when :SPEEDBOOST
            abilityscore+=25 if pbAIfaster?(nil,nil,i,@opponent) && ((@opponent.hp.to_f)/@opponent.totalhp<0.3)
            abilityscore+=25 if (@opponent.pbPartner.hp > 0 && pbAIfaster?(nil,nil,i,@opponent.pbPartner) && ((@opponent.pbPartner.hp.to_f)/@opponent.pbPartner.totalhp<0.3))
          when :JUSTIFIED
            abilityscore+=30 if (@opponent.pbPartner.hp > 0 && :DARK == checkAIbestMove().pbType(@opponent) || :DARK == checkAIbestMove(@opponent.pbPartner).pbType(@opponent.pbPartner))
          when :RATTLED
            abilityscore+=15 if [:DARK,:GHOST, :BUG].include?(checkAIbestMove().pbType(@opponent)) || (@opponent.pbPartner.hp > 0 && [:DARK,:GHOST, :BUG].include?(checkAIbestMove(@opponent.pbPartner).pbType(@opponent.pbPartner)))
          when :PRANKSTER
            abilityscore+=50 if !pbAIfaster?(nil,nil,i,@opponent) && !@opponent.hasType?(:DARK)
            abilityscore+=50 if (@opponent.pbPartner.hp > 0 && !pbAIfaster?(nil,nil,i,@opponent.pbPartner) && !@opponent.pbPartner.hasType?(:DARK))
          when :GALEWINGS
            abilityscore+=50 if !pbAIfaster?(nil,nil,i,@opponent) && i.hp==i.totalhp && !@attacker.pbOwnSide.effects[:StealthRock]
            abilityscore+=50 if @opponent.pbPartner.hp > 0 && !pbAIfaster?(nil,nil,i,@opponent.pbPartner) && i.hp==i.totalhp && !@attacker.pbOwnSide.effects[:StealthRock]
          when :BULLETPROOF
            abilityscore+=60 if (PBStuff::BULLETMOVE).include?(checkAIbestMove().move) || (@opponent.pbPartner.hp > 0 && (PBStuff::BULLETMOVE).include?(checkAIbestMove(@opponent.pbPartner).move))
          when :AURABREAK
            abilityscore+=50 if (@opponent.ability == :FAIRYAURA) || (@opponent.ability == :DARKAURA)
            abilityscore+=50 if (@opponent.pbPartner.hp > 0 && (@opponent.pbPartner.ability == :FAIRYAURA) || (@opponent.pbPartner.ability == :DARKAURA))
          when :PROTEAN, :LIBERO
            abilityscore+=40 if pbAIfaster?(nil,nil,i,@opponent) || (@opponent.pbPartner.hp > 0 && pbAIfaster?(nil,nil,i,@opponent.pbPartner))
          when :DANCER
            abilityscore+=30 if checkAImoves(PBStuff::DANCEMOVE,aimem)
            abilityscore+=30 if checkAImoves(PBStuff::DANCEMOVE,aimem2) && @mondata.skill>=BESTSKILL
          when :MERCILESS
            abilityscore+=50 if @opponent.status== :POISON || (@opponent.pbPartner.hp > 0 && @opponent.pbPartner.status== :POISON)
          # Gen 9 Mod - Added  Armour Tail
          when :DAZZLING,:QUEENLYMAJESTY,:ARMORTAIL,:QUICKREFLEX
            abilityscore+=20 if checkAIpriority(aimem)
            abilityscore+=20 if checkAIpriority(aimem2) && @mondata.skill>=BESTSKILL
          when :SANDSTREAM,:SNOWWARNING,:SANDSTREAM,:SNOWWARNING,:SANDSPIT
            abilityscore+=70 if (@opponent.ability == :WONDERGUARD)
            abilityscore+=70 if (@opponent.pbPartner.hp > 0 && (@opponent.pbPartner.ability == :WONDERGUARD))
          when :DEFEATIST
            abilityscore -= 80 if @attacker.hp != 0 # hard switch
          when :STURDY
            abilityscore -= 80 if @attacker.hp != 0 && i.hp == i.totalhp # hard switch
          when :ICESCALES
            abilityscore+=40 if @opponent.spatk> @opponent.attack
            abilityscore+=40 if @opponent.pbPartner.spatk> @opponent.pbPartner.attack
          when :MIRRORARMOR
            if @battle.FE == :STARLIGHT
              abilityscore+=20 if checkAIpriority(aimem)
              abilityscore+=20 if checkAIpriority(aimem2) && @mondata.skill>=BESTSKILL
            end
          when :UNSEENFIST
            if i.item != :PUNCHINGGLOVE
              abilityscore+=30 if checkAImoves(PBStuff::PROTECTMOVE,aimem)
              abilityscore+=30 if checkAImoves(PBStuff::PROTECTMOVE,aimem2) && @mondata.skill>=BESTSKILL
            end
          when :WINDPOWER # Gen 9 Mod - Added Wind Power
            abilityscore+=10 if checkAIbestMove(@opponent).windMove? || (@opponent.pbPartner.hp>0 && checkAIbestMove(@opponent.pbPartner).windMove?)
          when :WINDRIDER # Gen 9 Mod - Added Wind Rider
            abilityscore+=60 if checkAIbestMove(@opponent).windMove? || (@opponent.pbPartner.hp>0 && checkAIbestMove(@opponent.pbPartner).windMove?)
          when :THERMALEXCHANGE # Gen 9 Mod - Added Thermal Exchange
            abilityscore+=30 if (@opponent.pbPartner.hp > 0 && :DARK == checkAIbestMove().pbType(@opponent) || :DARK == checkAIbestMove(@opponent.pbPartner).pbType(@opponent.pbPartner))
          when :ELECTROMORPHOSIS # Gen 9 Mod - Added Electromorphosis
            abilityscore+=30 # I got no clue on the conditions, so i'mma just leave it at just a pure 30
        end
      end
      if transformed # pokemon has imposter ability. because we copy pokemon, we can use i to see ability opponent
        abilityscore += 50 if [:PUREPOWER, :HUGEPOWER, :MOXIE, :CHILLINGNEIGH, :GRIMNEIGH, :SPEEDBOOST, :BEASTBOOST, :SOULHEART, :WONDERGUARD, :PROTEAN, :LIBERO].include?(i.ability)
        abilityscore += 30 if i.level > nonmegaform.level || pbGetMonRoles(@opponent).include?(:SWEEPER)
        abilityscore = -200 if i.effects[:Substitute] > 0
        abilityscore = -500 if i.species == :DITTO
      end
      monscore += abilityscore
      PBDebug.log(sprintf("Abilities: %d", abilityscore)) if $INTERNAL
      # Items
      itemscore = 0
      if @mondata.skill>=HIGHSKILL
        if (i.item == :ROCKYHELMET)
          itemscore+=30 if (@opponent.ability == :SKILLLINK || @opponent.ability == :TECHLINK)
          itemscore+=30 if (@opponent.pbPartner.ability == :SKILLLINK || @opponent.pbPartner.ability == :TECHLINK)
          # Gen 9 Mod - Added Loaded Dice
          itemscore+=30 if (@opponent.item == :LOADEDDICE)
          itemscore+=30 if (@opponent.pbPartner.item == :LOADEDDICE)
          itemscore+=30 if checkAIbestMove(@opponent).contactMove? || (@opponent.pbPartner.hp > 0 && checkAIbestMove(@opponent.pbPartner).contactMove?)
        end
        if (i.item == :AIRBALLOON)
          allground=true
          for j in aimem
            allground=false if !(j.pbType(@opponent) == :GROUND)
          end
          if @mondata.skill>=BESTSKILL
          for j in aimem2
            allground=false if !(j.pbType(@opponent.pbPartner) == :GROUND)
          end
          end
          itemscore+=60 if :GROUND == checkAIbestMove().pbType(@opponent) || (@opponent.pbPartner.hp > 0 && :GROUND == checkAIbestMove(@opponent.pbPartner).pbType(@opponent.pbPartner))
          itemscore+=100 if allground
        end
        if (i.item == :FLOATSTONE)
          itemscore+=10 if checkAImoves([:LOWKICK,:GRASSKNOT],aimem)
        end
        if (i.item == :DESTINYKNOT)
          itemscore+=20 if (@opponent.ability == :CUTECHARM)
          itemscore+=20 if checkAImoves([:ATTRACT],aimem)
        end
        if (i.item == :ABSORBBULB)
          itemscore+=25 if :WATER == checkAIbestMove().pbType(@opponent) ||  (@opponent.pbPartner.hp > 0 && :WATER == checkAIbestMove(@opponent.pbPartner).pbType(@opponent.pbPartner))
        end
        if (i.item == :CELLBATTERY) && !(Rejuv && @battle.FE == :ELECTERRAIN)
          itemscore+=25 if :ELECTRIC == checkAIbestMove().pbType(@opponent) ||  (@opponent.pbPartner.hp > 0 && :ELECTRIC == checkAIbestMove(@opponent.pbPartner).pbType(@opponent.pbPartner))
        end
        if (i.item == :FOCUSSASH || (@battle.FE == :CHESS && i.pokemon.piece==:PAWN) || i.ability == :STURDY || (@battle.FE == :CHESS && i.ability == :STALWART)) && i.hp == i.totalhp
          # Gen 9 Mod - Hail/Snow/Both
          if   (((@battle.weather== :SANDSTORM && !(i.hasType?(:ROCK) || i.hasType?(:GROUND) || i.hasType?(:STEEL)))  || (@battle.weather== :HAIL && !(i.hasType?(:ICE) && (HAILSNOWMOD != "Snow" || KAIZOMOD)))) && !((i.ability == :OVERCOAT)))  || @attacker.pbOwnSide.effects[:StealthRock] ||
            @attacker.pbOwnSide.effects[:Spikes]>0 || @attacker.pbOwnSide.effects[:ToxicSpikes]>0
            if !(i.ability == :MAGICGUARD) && !(i.ability == :WONDERGUARD && @battle.FE == :COLOSSEUM)
              itemscore-=40
            end
          end
          if hard_switch # hard switch
            itemscore -= 80
          end
          itemscore+= (30)*@opponent.stages[PBStats::ATTACK]
          itemscore+= (30)*@opponent.stages[PBStats::SPATK]
          itemscore+= (30)*@opponent.stages[PBStats::SPEED]
        end
        if (i.item == :SNOWBALL)
            itemscore+=25 if :ICE == checkAIbestMove().pbType(@opponent) ||  (@opponent.pbPartner.hp > 0 && :ICE == checkAIbestMove(@opponent.pbPartner).pbType(@opponent.pbPartner))
        end
        if ((i.item == :PROTECTIVEPADS) || (i.item == :PUNCHINGGLOVE && move.punchMove?)) # Gen 9 Mod - Added Punching Glove
          itemscore+=25 if (i.ability == :EFFECTSPORE) || (i.ability == :STATIC) || (i.ability == :POISONPOINT) || (i.ability == :ROUGHSKIN) || (i.ability == :WANDERINGSPIRIT) || (i.ability == :PERISHBODY && @battle.FE != :HOLY)  || (i.ability == :IRONBARBS) || (i.ability == :FLAMEBODY) || (i.ability == :CUTECHARM) || (i.ability == :MUMMY) || (i.ability == :AFTERMATH) || (i.ability == :GOOEY) || ((i.ability == :FLUFFY) && (!@opponent.hasType?(:FIRE) && !@opponent.pbPartner.hasType?(:FIRE))) || (@opponent.item == :ROCKYHELMET) || (@opponent.ability == :TOXICDEBRIS) || (@opponent.ability == :LINGERINGAROMA) # Gen 9 Mod - Added Toxic Debris & Lingering Aroma
        end
        if i.item == :MAGICALSEED
          itemscore+=75 if (@battle.FE == :NEWWORLD || (!Rejuv && @battle.FE == :INVERSE)) && @attacker.hp != 0 #New World or Inverse Field, hard switch
        end
      end
      monscore+=itemscore
      PBDebug.log(sprintf("Items: %d",itemscore)) if $INTERNAL
      #Fields
      fieldscore=0
      if @mondata.skill>=BESTSKILL
        case @battle.FE
        when :ELECTERRAIN
            fieldscore+=50 if (i.ability == :SURGESURFER)
            fieldscore+=50 if Rejuv && (i.ability == :TERAVOLT)
            fieldscore+=25 if (i.ability == :GALVANIZE)
            fieldscore+=25 if Rejuv && (i.ability == :STEADFAST)
            fieldscore+=25 if Rejuv && (i.ability == :QUICKFEET)
            fieldscore+=25 if Rejuv && (i.ability == :LIGHTNINGROD)
            fieldscore+=25 if Rejuv && (i.ability == :BATTERY)
            fieldscore+=25 if (i.ability == :TRANSISTOR)
            fieldscore+=25 if i.hasType?(:ELECTRIC)
            fieldscore+=20 if Rejuv && (i.ability == :STATIC)
            fieldscore+=15 if Rejuv && (i.ability == :VOLTABSORB)
            # Gen 9 Mod - Added Hadron Engine
            fieldscore+=50 if (i.ability == :HADRONENGINE)
        when :GRASSY
            fieldscore+=30 if (i.ability == :GRASSPELT)
            fieldscore+=30 if (i.ability == :COTTONDOWN)
            fieldscore+=30 if Rejuv && (i.ability == :OVERGROW)
            fieldscore+=20 if Rejuv && (i.ability == :SAPSIPPER)
            fieldscore+=25 if Rejuv && (i.ability == :HARVEST)
            fieldscore+=25 if i.hasType?(:GRASS) || i.hasType?(:FIRE)
        when :MISTY
            fieldscore+=20 if i.hasType?(:FAIRY)
            fieldscore+=20 if (i.ability == :MARVELSCALE)
            fieldscore+=20 if (i.ability == :DRYSKIN)
            fieldscore+=20 if (i.ability == :WATERCOMPACTION)
            fieldscore+=25 if (i.ability == :PIXILATE)
            fieldscore+=25 if (i.ability == :SOULHEART)
          fieldscore+=20 if (i.ability == :PASTELVEIL)
        when :DARKCRYSTALCAVERN
            fieldscore+=30 if (i.ability == :PRISMARMOR)
            fieldscore+=30 if (i.ability == :SHADOWSHIELD)
        when :CHESS
            fieldscore+=10 if (i.ability == :ADAPTABILITY)
            fieldscore+=10 if (i.ability == :SYNCHRONIZE)
            fieldscore+=10 if (i.ability == :ANTICIPATION)
            fieldscore+=10 if (i.ability == :TELEPATHY)
            fieldscore+=30 if Rejuv && (i.ability == :STANCECHANGE)
            fieldscore+=25 if Rejuv && (i.ability == :STALL)
        when :BIGTOP
            fieldscore+=30 if (i.ability == :SHEERFORCE)
            fieldscore+=30 if (i.ability == :PUREPOWER)
            fieldscore+=30 if (i.ability == :HUGEPOWER)
            fieldscore+=30 if (i.ability == :GUTS)
            fieldscore+=10 if (i.ability == :DANCER)
            fieldscore+=20 if i.hasType?(:FIGHTING)
            fieldscore+=20 if (i.ability == :PUNKROCK)
        when :BURNING
            fieldscore+=25 if i.hasType?(:FIRE)
            fieldscore+=15 if (i.ability == :WATERVEIL)
          fieldscore+=15 if (i.ability == :HEATPROOF)
            fieldscore+=15 if (i.ability == :WATERBUBBLE)
          fieldscore+=30 if (i.ability == :FLASHFIRE)
            fieldscore+=30 if (i.ability == :FLAREBOOST)
            fieldscore+=30 if (i.ability == :BLAZE)
            fieldscore-=30 if (i.ability == :ICEBODY)
            fieldscore-=30 if (i.ability == :LEAFGUARD)
            fieldscore-=30 if (i.ability == :GRASSPELT)
            fieldscore-=30 if (i.ability == :FLUFFY)
        when :VOLCANIC
          fieldscore+=25 if i.hasType?(:FIRE)
          fieldscore+=15 if (i.ability == :WATERVEIL)
          fieldscore+=15 if (i.ability == :HEATPROOF)
          fieldscore+=15 if (i.ability == :WATERBUBBLE)
          fieldscore+=20 if (i.ability == :MAGMAARMOR) || (nonmegaform.ability == :MAGMAARMOR)
          fieldscore+=25 if (i.ability == :STEAMENGINE)
            fieldscore+=30 if (i.ability == :FLASHFIRE)
          fieldscore+=30 if (i.ability == :FLAREBOOST)
          fieldscore+=30 if (i.ability == :BLAZE)
          fieldscore-=30 if (i.ability == :ICEBODY)
          fieldscore-=30 if (i.ability == :LEAFGUARD)
          fieldscore-=30 if (i.ability == :GRASSPELT)
          fieldscore-=30 if (i.ability == :FLUFFY)
          fieldscore-=30 if (i.ability == :ICEFACE)
        when :SWAMP
            fieldscore+=15 if (i.ability == :GOOEY)
            fieldscore+=20 if (i.ability == :WATERCOMPACTION)
            fieldscore+=15 if (i.ability == :PROPELLERTAIL)
            fieldscore+=20 if (i.ability == :DRYSKIN)
            fieldscore+=20 if (i.ability == :WATERABSORB)
            fieldscore+=10 if ((i.ability == :RATTLED) || (nonmegaform.ability == :RATTLED))
        when :RAINBOW
            fieldscore+=10 if (i.ability == :WONDERSKIN)
            fieldscore+=20 if (i.ability == :MARVELSCALE)
            fieldscore+=25 if (i.ability == :SOULHEART)
            fieldscore+=30 if (i.ability == :CLOUDNINE)
            fieldscore+=30 if (i.ability == :PRISMARMOR)
            fieldscore+=20 if (i.ability == :PASTELVEIL)
        when :CORROSIVE
            fieldscore+=20 if (i.ability == :POISONHEAL)
            fieldscore+=25 if (i.ability == :TOXICBOOST)
            fieldscore+=30 if (i.ability == :MERCILESS)
            fieldscore+=30 if (i.ability == :CORROSION)
            fieldscore+=15 if i.hasType?(:POISON)
        when :CORROSIVEMIST
            fieldscore+=10 if (i.ability == :WATERCOMPACTION)
            fieldscore+=20 if (i.ability == :POISONHEAL)
            fieldscore+=25 if (i.ability == :TOXICBOOST)
            fieldscore+=30 if (i.ability == :MERCILESS)
            fieldscore+=30 if (i.ability == :CORROSION)
            fieldscore+=15 if i.hasType?(:POISON)
        when :DESERT
            fieldscore+=20 if ((i.ability == :SANDSTREAM) || (nonmegaform.ability == :SANDSTREAM) || (i.ability == :SANDSPIT) || (nonmegaform.ability == :SANDSPIT))
            fieldscore+=25 if (i.ability == :SANDVEIL)
            fieldscore+=30 if (i.ability == :SANDFORCE)
            fieldscore+=50 if (i.ability == :SANDRUSH)
            fieldscore+=20 if i.hasType?(:GROUND)
            fieldscore-=25 if i.hasType?(:ELECTRIC)
        when :ICY
            fieldscore+=25 if i.hasType?(:ICE)
            fieldscore+=25 if (i.ability == :ICEBODY)
            fieldscore+=25 if (i.ability == :SNOWCLOAK)
            fieldscore+=25 if (i.ability == :REFRIGERATE)
            fieldscore+=50 if (i.ability == :SLUSHRUSH) || (i.item == :EMPCREST && i.species == :EMPOLEON)
        when :ROCKY
            fieldscore-=15 if (i.ability == :GORILLATACTICS)
        when :FOREST
            fieldscore+=20 if (i.ability == :SAPSIPPER)
            fieldscore+=25 if i.hasType?(:GRASS) || i.hasType?(:BUG)
            fieldscore+=30 if (i.ability == :GRASSPELT)
            fieldscore+=30 if (i.ability == :OVERGROW)
            fieldscore+=30 if (i.ability == :SWARM)
          fieldscore+=20 if (i.ability == :EFFECTSPORE)
        when :SUPERHEATED
            fieldscore+=15 if i.hasType?(:FIRE)
        when :VOLCANICTOP
          fieldscore += 15 if i.hasType?(:FIRE)
          fieldscore += 25 if i.ability == :STEAMENGINE
          fieldscore -= 30 if i.ability == :ICEFACE
          fieldscore += 30 if i.ability == :GALEWINGS && @battle.pbWeather == :STRONGWINDS
        when :FACTORY
            fieldscore+=25 if i.hasType?(:ELECTRIC)
            fieldscore+=20 if (i.ability == :MOTORDRIVE)
            fieldscore+=20 if (i.ability == :STEELWORKER)
            fieldscore+=25 if (i.ability == :DOWNLOAD)
            fieldscore+=25 if (i.ability == :TECHNICIAN)
            fieldscore+=25 if (i.ability == :TECHLINK)
            fieldscore+=25 if (i.ability == :GALVANIZE)
        when :SHORTCIRCUIT
            fieldscore+=20 if (i.ability == :VOLTABSORB)
            fieldscore+=20 if (i.ability == :STATIC)
            fieldscore+=25 if (i.ability == :GALVANIZE)
            fieldscore+=50 if (i.ability == :SURGESURFER)
            fieldscore+=20 if (Rejuv && i.ability == :DOWNLOAD)
            fieldscore+=25 if i.hasType?(:ELECTRIC)
        when :WASTELAND
            fieldscore+=10 if i.hasType?(:POISON)
            fieldscore+=10 if (i.ability == :CORROSION)
            fieldscore+=20 if (i.ability == :POISONHEAL)
            fieldscore+=20 if (i.ability == :EFFECTSPORE)
            fieldscore+=20 if (i.ability == :POISONPOINT)
            fieldscore+=20 if (i.ability == :STENCH)
            fieldscore+=20 if (i.ability == :GOOEY)
            fieldscore+=25 if (i.ability == :TOXICBOOST)
            fieldscore+=30 if (i.ability == :MERCILESS)
        when :ASHENBEACH
            fieldscore+=10 if i.hasType?(:FIGHTING)
            fieldscore+=15 if (i.ability == :INNERFOCUS)
            fieldscore+=15 if (i.ability == :OWNTEMPO)
            fieldscore+=15 if (i.ability == :PUREPOWER)
            fieldscore+=15 if (i.ability == :STEADFAST)
            fieldscore+=20 if ((i.ability == :SANDSTREAM) || (nonmegaform.ability == :SANDSTREAM))
            fieldscore+=20 if (i.ability == :WATERCOMPACTION)
            fieldscore+=30 if (i.ability == :SANDFORCE)
            fieldscore+=35 if (i.ability == :SANDVEIL)
            fieldscore+=50 if (i.ability == :SANDRUSH)
        when :WATERSURFACE
            fieldscore+=25 if i.hasType?(:WATER)
            fieldscore+=25 if i.hasType?(:ELECTRIC)
            fieldscore+=25 if (i.ability == :WATERVEIL)
            fieldscore+=25 if (i.ability == :HYDRATION)
            fieldscore+=25 if (i.ability == :TORRENT)
            fieldscore+=25 if (i.ability == :SCHOOLING)
            fieldscore+=25 if (i.ability == :WATERCOMPACTION)
            fieldscore+=50 if (i.ability == :SWIFTSWIM)
            fieldscore+=50 if (i.ability == :SURGESURFER)
            fieldscore+=25 if (i.ability == :STEAMENGINE)
            mod1=PBTypes.oneTypeEff(:WATER,i.type1)
            mod2=(i.type1==i.type2 || i.type2.nil?) ? 2 : PBTypes.oneTypeEff(:WATER,i.type2)
            fieldscore-=50 if mod1*mod2>4
        when :UNDERWATER
            fieldscore+=25 if i.hasType?(:WATER)
            fieldscore+=25 if i.hasType?(:ELECTRIC)
            fieldscore+=25 if (i.ability == :WATERVEIL)
            fieldscore+=25 if (i.ability == :HYDRATION)
            fieldscore+=25 if (i.ability == :TORRENT)
            fieldscore+=25 if (i.ability == :SCHOOLING)
            fieldscore+=25 if (i.ability == :WATERCOMPACTION)
            fieldscore+=50 if (i.ability == :SWIFTSWIM)
            fieldscore+=50 if (i.ability == :SURGESURFER)
            fieldscore+=25 if (i.ability == :STEAMENGINE)
            mod1=PBTypes.oneTypeEff(:WATER,i.type1)
            mod2=(i.type1==i.type2 || i.type2.nil?) ? 2 : PBTypes.oneTypeEff(:WATER,i.type2)
            fieldscore-=50 if mod1*mod2>4
        when :CAVE
            fieldscore+=15 if i.hasType?(:GROUND)
        when :GLITCH
            fieldscore+=20 if (Rejuv && i.ability == :DOWNLOAD)
        when :CRYSTALCAVERN
            fieldscore+=25 if i.hasType?(:DRAGON)
            fieldscore+=30 if (i.ability == :PRISMARMOR)
        when :MURKWATERSURFACE
            fieldscore+=25 if i.hasType?(:WATER)
            fieldscore+=25 if i.hasType?(:POISON)
            fieldscore+=25 if i.hasType?(:ELECTRIC)
            fieldscore+=25 if (i.ability == :SCHOOLING)
            fieldscore+=25 if (i.ability == :WATERCOMPACTION)
            fieldscore+=25 if (i.ability == :TOXICBOOST)
            fieldscore+=25 if (i.ability == :POISONHEAL)
            fieldscore+=25 if (i.ability == :MERCILESS)
            fieldscore+=50 if (i.ability == :SWIFTSWIM)
            fieldscore+=50 if (i.ability == :SURGESURFER)
            fieldscore+=20 if (i.ability == :GOOEY)
            fieldscore+=20 if (i.ability == :STENCH)
        when :MOUNTAIN
            fieldscore += 25 if i.hasType?(:ROCK)
            fieldscore += 25 if i.hasType?(:FLYING)
            fieldscore += 20 if i.ability == :SNOWWARNING || nonmegaform.ability == :SNOWWARNING
            fieldscore += 20 if i.ability == :DROUGHT || nonmegaform.ability == :DROUGHT
            fieldscore += 25 if i.ability == :LONGREACH
            fieldscore += 30 if i.ability == :GALEWINGS && @battle.pbWeather == :STRONGWINDS
        when :SNOWYMOUNTAIN
            fieldscore += 25 if i.hasType?(:ROCK)
            fieldscore += 25 if i.hasType?(:FLYING)
            fieldscore += 25 if i.hasType?(:ICE)
            fieldscore += 20 if i.ability == :SNOWWARNING || nonmegaform.ability == :DROUGHT
            fieldscore += 20 if i.ability == :DROUGHT || nonmegaform.ability == :DROUGHT
            fieldscore += 20 if i.ability == :ICEBODY
            fieldscore += 20 if i.ability == :SNOWCLOAK
            fieldscore += 25 if i.ability == :LONGREACH
            fieldscore += 25 if i.ability == :REFRIGERATE
            fieldscore += 30 if i.ability == :GALEWINGS && @battle.pbWeather == :STRONGWINDS
            fieldscore += 50 if (i.ability == :SLUSHRUSH) || (i.item == :EMPCREST && i.species == :EMPOLEON)
        when :HOLY
            fieldscore+=20 if i.hasType?(:NORMAL)
            fieldscore+=20 if (i.ability == :JUSTIFIED)
          fieldscore+=25 if i.ability == :POWERSPOT
        when :MIRROR
          fieldscore+=25 if (i.ability == :SANDVEIL)
            fieldscore+=25 if (i.ability == :SNOWCLOAK)
            fieldscore+=25 if (i.ability == :ILLUSION)
            fieldscore+=25 if (i.ability == :TANGLEDFEET)
            fieldscore+=25 if (i.ability == :MAGICBOUNCE)
            fieldscore+=25 if (i.ability == :COLORCHANGE)
        when :FAIRYTALE
            fieldscore+=25 if i.hasType?(:FAIRY)
            fieldscore+=25 if i.hasType?(:STEEL)
            fieldscore+=40 if i.hasType?(:DRAGON)
            fieldscore+=25 if (i.ability == :POWEROFALCHEMY)
            fieldscore+=25 if (i.ability == :MIRRORARMOR) || (nonmegaform.ability == :MIRRORARMOR)
            fieldscore+=25 if (i.ability == :PASTELVEIL)
            fieldscore+=25 if (i.ability == :MAGICGUARD) || (nonmegaform.ability == :MAGICGUARD)
            fieldscore+=25 if (i.ability == :MAGICBOUNCE)
            fieldscore+=25 if (i.ability == :FAIRYAURA)
            fieldscore+=25 if (i.ability == :BATTLEARMOR) || (nonmegaform.ability == :BATTLEARMOR)
            fieldscore+=25 if (i.ability == :SHELLARMOR) || (nonmegaform.ability == :SHELLARMOR)
            fieldscore+=25 if (i.ability == :MAGICIAN)
            fieldscore+=25 if (i.ability == :MARVELSCALE)
            fieldscore+=30 if (i.ability == :STANCECHANGE)
            fieldscore+=50 if (i.ability == :DAUNTLESSSHIELD)
            fieldscore+=50 if (i.ability == :INTREPIDSWORD)
        when :DRAGONSDEN
            fieldscore+=25 if i.hasType?(:FIRE)
            fieldscore+=50 if i.hasType?(:DRAGON)
            fieldscore+=20 if (i.ability == :MARVELSCALE)
            fieldscore+=20 if (i.ability == :MULTISCALE)
            fieldscore+=20 if ((i.ability == :MAGMAARMOR) || (nonmegaform.ability == :MAGMAARMOR))
        when :FLOWERGARDEN1,:FLOWERGARDEN2,:FLOWERGARDEN3,:FLOWERGARDEN4,:FLOWERGARDEN5
            fieldscore+=25 if i.hasType?(:GRASS)
            fieldscore+=25 if i.hasType?(:BUG)
            fieldscore+=20 if (i.ability == :FLOWERGIFT)
            fieldscore+=20 if (i.ability == :FLOWERVEIL)
            fieldscore+=20 if ((i.ability == :DROUGHT) || (nonmegaform.ability == :DROUGHT))
            fieldscore+=20 if ((i.ability == :DRIZZLE) || (nonmegaform.ability == :DRIZZLE))
            fieldscore+=20 if Rejuv && ((i.ability == :GRASSYSURGE) || (nonmegaform.ability == :GRASSYSURGE))
            fieldscore+=15 if (i.ability == :SEEDSOWER || (nonmegaform.ability == :SEEDSOWER)) # Gen 9 Mod - Added Seed Sower
            fieldscore+=25 if (i.ability == :RIPEN)
        when :STARLIGHT
            fieldscore+=25 if i.hasType?(:PSYCHIC)
            fieldscore+=25 if i.hasType?(:FAIRY)
            fieldscore+=25 if i.hasType?(:DARK)
            fieldscore+=20 if (i.ability == :MARVELSCALE)
            fieldscore+=20 if (i.ability == :VICTORYSTAR)
            fieldscore+=25 if ((i.ability == :ILLUMINATE) || (nonmegaform.ability == :ILLUMINATE))
            fieldscore+=30 if (i.ability == :SHADOWSHIELD)
        when :NEWWORLD
            fieldscore+=25 if i.hasType?(:FLYING)
            fieldscore+=25 if i.hasType?(:DARK)
            fieldscore+=20 if (i.ability == :VICTORYSTAR)
            fieldscore+=25 if (i.ability == :LEVITATE || i.ability == :SOLARIDOL || i.ability == :LUNARIDOL)
            fieldscore+=30 if (i.ability == :SHADOWSHIELD)
        when :INVERSE
            fieldscore+=10 if i.hasType?(:NORMAL)
            fieldscore+=10 if i.hasType?(:ICE)
            fieldscore-=10 if i.hasType?(:FIRE)
            fieldscore-=30 if i.hasType?(:STEEL)
        when :PSYTERRAIN
          fieldscore+=25 if i.hasType?(:PSYCHIC)
            fieldscore+=20 if (i.ability == :PUREPOWER)
            fieldscore+=20 if ((i.ability == :ANTICIPATION) || (nonmegaform.ability == :ANTICIPATION))
          fieldscore+=20 if Rejuv && ((i.ability == :FOREWARN) || (nonmegaform.ability == :FOREWARN))
            fieldscore+=50 if (i.ability == :TELEPATHY)
          fieldscore+=25 if i.ability == :POWERSPOT
        when :DIMENSIONAL
          fieldscore+=25 if i.hasType?(:DARK)
          #fieldscore+=30 if (i.ability == :ANGERSHELL) # Gen 9 Mod - Added Anger Shell / On base mod, it isn't affected by the field
          fieldscore+=30 if (i.ability == :SHADOWSHIELD)
          fieldscore+=30 if (i.ability == :BEASTBOOST)
          fieldscore+=30 if (i.ability == :PERSIHBODY)
          fieldscore+=20 if ((i.ability == :RATTLED) || (nonmegaform.ability == :RATTLED))
          fieldscore+=20 if ((i.ability == :BERSERK) || (nonmegaform.ability == :BERSERK))
          fieldscore+=20 if ((i.ability == :ANGERPOINT) || (nonmegaform.ability == :ANGERPOINT))
          fieldscore+=20 if ((i.ability == :JUSTIFIED) || (nonmegaform.ability == :JUSTIFIED))
          fieldscore+=20 if ((i.ability == :PRESSURE) || (nonmegaform.ability == :PRESSURE))
          fieldscore+=20 if ((i.ability == :UNNERVE) || (nonmegaform.ability == :UNNERVE))
        when :FROZENDIMENSION
          fieldscore+=25 if i.hasType?(:ICE)
          fieldscore+=25 if i.hasType?(:DARK)
          fieldscore+=25 if (i.ability == :ICEBODY)
            fieldscore+=25 if (i.ability == :SNOWCLOAK)
            fieldscore+=25 if (i.ability == :REFRIGERATE)
          #fieldscore+=35 if (i.ability == :ANGERSHELL) # Gen 9 Mod - Added Anger Shell / On base mod, it isn't affected by the field
            fieldscore+=50 if (i.ability == :SLUSHRUSH) || (i.item == :EMPCREST && i.species == :EMPOLEON)
          fieldscore+=25 if (i.ability == :ICEFACE)
          fieldscore+=20 if ((i.ability == :RATTLED) || (nonmegaform.ability == :RATTLED))
          fieldscore+=20 if ((i.ability == :BERSERK) || (nonmegaform.ability == :BERSERK))
          fieldscore+=20 if ((i.ability == :ANGERPOINT) || (nonmegaform.ability == :ANGERPOINT))
          fieldscore+=20 if ((i.ability == :JUSTIFIED) || (nonmegaform.ability == :JUSTIFIED))
          fieldscore+=20 if ((i.ability == :PRESSURE) || (nonmegaform.ability == :PRESSURE))
          fieldscore+=20 if ((i.ability == :UNNERVE) || (nonmegaform.ability == :UNNERVE))
        when :HAUNTED
          fieldscore+=25 if i.hasType?(:GHOST)
          fieldscore+=25 if i.ability == :RATTLED
          fieldscore+=15 if i.ability == :CURSEDBODY
          fieldscore+=25 if i.ability == :PERISHBODY
          fieldscore+=25 if i.ability == :POWERSPOT
        when :CORRUPTED
          fieldscore+=25 if i.hasType?(:POISON)
          fieldscore-=25 if [:GRASSPELT,:LEAFGUARD,:FLOWERVEIL].include?(i.ability)
          fieldscore+=25 if i.ability == :POISONHEAL
          fieldscore+=15 if [:WONDERSKIN,:IMMUNITY,:PASTERLVEIL].include?(i.ability)
          fieldscore+=15 if [:POISONTOUCH,:POISONPOINT].include?(i.ability)
          fieldscore+=15 if i.ability == :LIQUIDOOZE
          fieldscore+=30 if [:TOXICBOOST,:CORROSION].include?(i.ability)
          if i.ability == :DRYSKIN
            fieldscore+=25 if i.hasType?(:POISON)
            fieldscore-=25 if !i.hasType?(:POISON)
          end
        when :BEWITCHED
          fieldscore+=20 if i.ability == :FLOWERVEIL
            fieldscore+=25 if i.hasType?(:GRASS) || i.hasType?(:FAIRY)
            fieldscore+=25 if i.ability == :NATURALCURE
            fieldscore+=25 if i.ability == :PASTELVEIL
          fieldscore+=25 if i.ability == :COTTONDOWN
            fieldscore+=25 if i.ability == :POWERSPOT
          fieldscore+=20 if i.ability == :EFFECTSPORE
        when :SKY
          fieldscore+=15 if i.ability == :EARLYBIRD
          fieldscore+=15 if i.ability == :CLOUDNINE
            fieldscore+=25 if i.hasType?(:FLYING)
            fieldscore+=25 if i.ability == :GALEWINGS
            fieldscore+=25 if i.ability == :BIGPECKS || nonmegaform.ability == :BIGPECKS
          fieldscore+=25 if i.ability == :LEVITATE || nonmegaform.ability == :LEVITATE
          fieldscore+=25 if i.ability == :SOLARIDOL || nonmegaform.ability == :SOLARIDOL
          fieldscore+=25 if i.ability == :LUNARIDOL || nonmegaform.ability == :LUNARIDOL
            fieldscore+=25 if i.ability == :AERILATE
          fieldscore+=30 if i.ability == :LONGREACH
        when :INFERNAL
          fieldscore+=25 if i.hasType?(:FIRE)
          fieldscore+=25 if i.hasType?(:DARK)
          fieldscore+=25 if (i.ability == :PERSIHBODY)
          fieldscore+=30 if (i.ability == :MAGMAARMOR) || (nonmegaform.ability == :MAGMAARMOR)
          fieldscore+=20 if (i.ability == :FLAMEBODY) || (nonmegaform.ability == :FLAMEBODY)
          fieldscore+=20 if (i.ability == :DESOLATELAND) || (nonmegaform.ability == :DESOLATELAND)
          fieldscore+=25 if (i.ability == :STEAMENGINE)
            fieldscore+=30 if (i.ability == :FLASHFIRE)
          fieldscore+=30 if (i.ability == :FLAREBOOST)
          fieldscore+=30 if (i.ability == :BLAZE)
          fieldscore-=20 if (i.ability == :PASTELVEIL)
          fieldscore-=30 if (i.ability == :ICEFACE)
        when :COLOSSEUM
          fieldscore+=15 if i.ability == :STALWART
          fieldscore+=20 if i.ability == :DEFIANT
          fieldscore+=20 if i.ability == :COMPETITIVE
          fieldscore-=30 if i.ability == :RATTLED || i.ability == :WIMPOUT
            fieldscore+=25 if i.ability == :WONDERGUARD
          fieldscore+=25 if i.ability == :QUICKDRAW
          fieldscore+=25 if i.ability == :EMERGENCYEXIT
            fieldscore+=25 if (i.ability == :BATTLEARMOR) || (nonmegaform.ability == :BATTLEARMOR)
            fieldscore+=25 if (i.ability == :SHELLARMOR) || (nonmegaform.ability == :SHELLARMOR)
          fieldscore+=25 if (i.ability == :MIRRORARMOR) || (nonmegaform.ability == :MIRRORARMOR)
            fieldscore+=25 if (i.ability == :MAGICGUARD) || (nonmegaform.ability == :MAGICGUARD)
            fieldscore+=25 if i.ability == :SKILLLINK || i.ability == :TECHLINK
          fieldscore+=30 if i.ability == :NOGUARD || (nonmegaform.ability == :NOGUARD)
          fieldscore+=50 if (i.ability == :DAUNTLESSSHIELD)
            fieldscore+=50 if (i.ability == :INTREPIDSWORD)
        when :CONCERT1,:CONCERT2,:CONCERT3,:CONCERT4
          fieldscore+=25 if (i.ability == :TECHNICIAN)
          fieldscore+=25 if (i.ability == :TECHLINK)
          fieldscore+=25 if ([:HEAVYMETAL,:SOLIDROCK,:PUNKROCK,:ROCKHEAD,:SOUNDPROOF].include?(i.ability))
          fieldscore+=15 if ([:HEAVYMETAL,:SOLIDROCK,:PUNKROCK,:GALVANIZE,:PLUS].include?(i.ability)) && @battle.ProgressiveFieldCheck(PBFields::CONCERT,1,3)
          fieldscore-=15 if ([:KLUTZ,:MINUS].include?(i.ability)) && @battle.ProgressiveFieldCheck(PBFields::CONCERT,2,4)
          fieldscore+=25 if ([:RUNAWAY,:EMERGENCYEXIT].include?(i.ability)) && @battle.ProgressiveFieldCheck(PBFields::CONCERT,2,4)
          fieldscore+=30 if (i.ability == :RATTLED) && @battle.ProgressiveFieldCheck(PBFields::CONCERT,3,4)
        when :BACKALLEY
          fieldscore+=25 if i.hasType?(:DARK)
          fieldscore+=20 if i.hasType?(:POISON)
          fieldscore+=20 if i.hasType?(:BUG)
          fieldscore+=20 if i.hasType?(:STEEL)
          fieldscore-=25 if i.hasType?(:FAIRY)
          fieldscore+=20 if (i.ability == :STENCH)
          fieldscore+=25 if (i.ability == :DOWNLOAD)
          fieldscore+=25 if ((i.ability == :PICKPOCKET) || (nonmegaform.ability == :PICKPOCKET))
          fieldscore+=25 if ((i.ability == :MERCILESS) || (nonmegaform.ability == :MERCILESS))
          fieldscore+=25 if ((i.ability == :MAGICIAN) || (nonmegaform.ability == :MAGICIAN))
          fieldscore+=25 if ((i.ability == :ANTICIPATION) || (nonmegaform.ability == :ANTICIPATION))
          fieldscore+=25 if ((i.ability == :FOREWARN) || (nonmegaform.ability == :FOREWARN))
          fieldscore+=25 if ((i.ability == :RATTLED) || (nonmegaform.ability == :RATTLED))
          fieldscore+=20 if i.ability == :DEFIANT
        when :CITY
          fieldscore+=25 if i.hasType?(:NORMAL)
          fieldscore+=20 if i.hasType?(:POISON)
          fieldscore+=20 if i.hasType?(:BUG)
          fieldscore+=20 if i.hasType?(:STEEL)
          fieldscore-=20 if i.hasType?(:FAIRY)
          fieldscore+=20 if (i.ability == :STENCH)
          fieldscore+=25 if (i.ability == :DOWNLOAD)
          fieldscore+=25 if ((i.ability == :BIGPECKS) || (nonmegaform.ability == :BIGPECKS))
          fieldscore+=25 if ((i.ability == :PICKUP) || (nonmegaform.ability == :PICKUP))
          fieldscore+=25 if ((i.ability == :EARLYBIRD) || (nonmegaform.ability == :EARLYBIRD))
          fieldscore+=25 if ((i.ability == :RATTLED) || (nonmegaform.ability == :RATTLED))
          fieldscore+=20 if (i.ability == :HUSTLE)
          fieldscore+=20 if ((i.ability == :FRISK) || (nonmegaform.ability == :FRISK))
          fieldscore+=20 if i.ability == :COMPETITIVE
        when :CLOUDS
          fieldscore+=25 if i.hasType?(:FLYING)
          fieldscore+=20 if (i.ability == :CLOUDNINE)
          fieldscore+=20 if (i.ability == :FLUFFY)
          fieldscore+=20 if (i.ability == :HYDRATION)
          fieldscore+=20 if (i.ability == :FORECAST)
          fieldscore+=20 if (i.ability == :OVERCOAT)
        when :DARKNESS1
          fieldscore+=10 if i.hasType?(:DARK)
          fieldscore+=10 if (i.ability == :DARKAURA)
          fieldscore-=10 if (i.ability == :FAIRYAURA)
          fieldscore+=20 if (i.ability == :RATTLED)
        when :DARKNESS2
          fieldscore+=20 if i.hasType?(:DARK)
          fieldscore+=20 if (i.ability == :DARKAURA)
          fieldscore-=20 if (i.ability == :FAIRYAURA)
          fieldscore+=20 if (i.ability == :RATTLED)
          fieldscore-=20 if (i.ability == :INSOMNIA)
          fieldscore+=20 if (i.ability == :BADDREAMS)
          fieldscore+=20 if (i.ability == :SHADOWSHIELD)
        when :DARKNESS3
          fieldscore+=40 if i.hasType?(:DARK)
          fieldscore+=40 if (i.ability == :DARKAURA)
          fieldscore-=40 if (i.ability == :FAITTLED)
          fieldscore-=20 if (i.ability == :INSOMNIA)
          fieldscore+=40 if (i.ability == :BADDREAMS)
          fieldscore+=20 if (i.ability == :SHADOWSHIELD)
        when :DANCEFLOOR
          fieldscore+=10 if i.hasType?(:GHOST)
          fieldscore+=10 if i.hasType?(:DARK)
          fieldscore+=20 if i.hasType?(:PSYCHIC)
          fieldscore+=20 if (i.ability == :INSOMNIA)
          fieldscore+=20 if (i.ability == :MAGICGUARD)
          fieldscore+=10 if (i.ability == :MAGICIAN)
          fieldscore+=40 if (i.ability == :DANCER)
          fieldscore+=20 if (i.ability == :ILLUMINATE)
        when :CROWD
          fieldscore+=20 if (i.ability == :GUTS)
          fieldscore+=10 if (i.ability == :INNERFOCUS)
          fieldscore+=30 if (i.ability == :INTIMIDATE)
          fieldscore+=20 if (i.ability == :IRONFIST)
        end
      end
      monscore += fieldscore
      PBDebug.log(sprintf("Fields: %d",fieldscore)) if $INTERNAL
      #Other
      otherscore = 0
      otherscore -= 70 if hard_switch && @attacker.species == i.species
      otherscore -= 100 if @opponent.ability == :WONDERGUARD && roughdamagearray[0].max == 0
      if @attacker.effects[:FutureSight] >= 1
        move, moveuser = @attacker.pbFutureSightUserPlusMove
        damage = hard_switch ? pbRoughDamage(move,moveuser,nonmegaform) : pbRoughDamage(move,moveuser,i)
        otherscore += 50 if damage == 0
        otherscore += 50 if damage < i.hp
        otherscore += 50 if 2*damage < i.hp
        otherscore -= 100 if damage > i.hp
      end

      monscore += otherscore
      PBDebug.log(sprintf("Other Score: %d",otherscore)) if $INTERNAL

      if @attacker.pbOwnSide.effects[:StealthRock] || @attacker.pbOwnSide.effects[:Spikes]>0
        monscore= (monscore*(i.hp.to_f/i.totalhp.to_f)).floor
      end
      hazpercent = totalHazardDamage(nonmegaform)
      monscore=1 if hazpercent>(i.hp.to_f/i.totalhp)*100
      # more likely to send out ace the fewer party members are alive
      partyacedrop = 0.9 - 0.1 * party.count {|mon| mon && mon.hp > 0}

      monscore*= partyacedrop if theseRoles.include?(:ACE) && @mondata.skill>=BESTSKILL
      #Final score
      monscore.floor
      PBDebug.log(sprintf("Final Pokemon Score: %d \n",monscore)) if $INTERNAL
      $ai_log_data[@attacker.index].switch_scores.push(monscore)
      $ai_log_data[@attacker.index].switch_name.push(getMonName(i.pokemon.species))
      partyScores.push(monscore)
    end

    # NOT DOING BEFORE E19 PUBLIC RELEASE
    # If the whole party would just die, check specific things
    if survivors.none? {|lives| lives}
      # aftermath
      # intimidate
      # check any move that moves before opponent
      # and see if it does anything useful, even tho not kills
      # then modify scores based on that
    end
    return partyScores
  end

  #should the current @attacker switch out?
  def shouldSwitch?
    return -1000 if !@battle.opponent && @battle.pbIsOpposing?(@attacker.index)
    return -1000 if @battle.pbPokemonCount(@mondata.party) == 1
    return -1000 if $game_switches[:Last_Ace_Switch] && @battle.pbPokemonCount(@mondata.party) == 2
    return -1000 if @attacker.issossmon
    if @attacker.isbossmon
      return -1000 if @attacker.chargeAttack
    end
    count = 0
    for i in 0..(@mondata.party.length-1)
      next if !@battle.pbCanSwitch?(@attacker.index,i,false)
      count+=1
    end
    return -1000 if count==0
    return 100 if @attacker.ability == :ZEROTOHERO && attacker.form == 0 && !pbAIfaster?()
    aimem = getAIMemory(@opponent)
    aimem2 = getAIMemory(@opponent.pbPartner)
    statusscore = 0
    statscore = 0
    healscore = 0
    forcedscore = 0
    typescore = 0
    specialscore = 0
    #Statuses
    statusscore+=80 if @attacker.effects[:Curse]
    statusscore+=60 if @attacker.effects[:LeechSeed]>=0
    statusscore+=60 if @attacker.effects[:Attract]>=0
    statusscore+=80 if @attacker.effects[:Confusion]>0
    # Gen 9 Mod - Encourage switching if being salt cured.
    statusscore+=60 if @attacker.effects[:SaltCure]
    statusscore+=80 if @attacker.effects[:SaltCure] && (@attacker.hasType?(:WATER) || @attacker.hasType?(:STEEL))
    if @attacker.effects[:PerishSong]==2
      statusscore+=40
    elsif @attacker.effects[:PerishSong]==1
      statusscore+=200
    end
    statusscore+= (@attacker.effects[:Toxic]*15) if @attacker.effects[:Toxic]>0
    statusscore+=50 if @attacker.ability == :NATURALCURE && !@attacker.status.nil?
    statusscore+=60 if @mondata.partyroles.any? {|roles| roles.include?(:CLERIC)} && !@attacker.status.nil?
    if @attacker.status== :SLEEP
      statusscore+=170 if checkAImoves([:DREAMEATER,:NIGHTMARE],aimem)
    end
    statusscore+=95 if @attacker.effects[:Yawn]>0 && @attacker.status!=:SLEEP
    PBDebug.log(sprintf("Initial switchscore building: Statuses (%d)",statusscore)) if $INTERNAL
    #Stat changes
    specialmove = false
    physmove = false
    for i in @attacker.moves
      next if i.nil?
      specialmove = true if i.pbIsSpecial?()
      physmove = true if i.pbIsPhysical?()
    end
    if @mondata.roles.include?(:SWEEPER)
      statscore+= (-30)*@attacker.stages[PBStats::ATTACK] if @attacker.stages[PBStats::ATTACK]<0 && physmove
      statscore+= (-30)*@attacker.stages[PBStats::SPATK] if @attacker.stages[PBStats::SPATK]<0 && specialmove
      statscore+= (-30)*@attacker.stages[PBStats::SPEED] if @attacker.stages[PBStats::SPEED]<0
      statscore+= (-30)*@attacker.stages[PBStats::ACCURACY] if @attacker.stages[PBStats::ACCURACY]<0
    else
      statscore+= (-15)*@attacker.stages[PBStats::ATTACK] if @attacker.stages[PBStats::ATTACK]<0 && physmove
      statscore+= (-15)*@attacker.stages[PBStats::SPATK] if @attacker.stages[PBStats::SPATK]<0 && specialmove
      statscore+= (-15)*@attacker.stages[PBStats::SPEED] if @attacker.stages[PBStats::SPEED]<0
      statscore+= (-15)*@attacker.stages[PBStats::ACCURACY] if @attacker.stages[PBStats::ACCURACY]<0
    end
    if @mondata.roles.include?(:PHYSICALWALL)
      statscore+= (-30)*@attacker.stages[PBStats::DEFENSE] if @attacker.stages[PBStats::DEFENSE]<0
    else
      statscore+= (-15)*@attacker.stages[PBStats::DEFENSE] if @attacker.stages[PBStats::DEFENSE]<0
    end
    if @mondata.roles.include?(:SPECIALWALL)
      statscore+= (-30)*@attacker.stages[PBStats::SPDEF] if @attacker.stages[PBStats::SPDEF]<0
    else
      statscore+= (-15)*@attacker.stages[PBStats::SPDEF] if @attacker.stages[PBStats::SPDEF]<0
    end
    PBDebug.log(sprintf("Initial switchscore building: Stat Stages (%d)",statscore)) if $INTERNAL
    #Healing potential
    healscore+=30 if (@attacker.hp.to_f)/@attacker.totalhp<(2/3) && @attacker.ability == :REGENERATOR
    healscore+=30 if (@attacker.pbPartner.hp.to_f)/@attacker.pbPartner.totalhp<(3/4) && @attacker.ability == :HOSPITALITY
    if @attacker.effects[:Wish]>0
      for i in @mondata.party
        next if i.nil? || i.hp == 0 || @mondata.party.index(i) == @attacker.pokemonIndex
        if i.hp > 0.3*i.totalhp && i.hp < 0.6*i.totalhp
          healscore+=40
          break
        end
      end
    end
    PBDebug.log(sprintf("Initial switchscore building: Healing (%d)",healscore)) if $INTERNAL
    #Force-out conditions
    bothimmune = true
    bothimmune = false if @attacker.species==:COSMOEM && Reborn # for postgame only
    for i in @attacker.moves
      next if i.nil?
      tricktreat = true if i.move==:TRICKORTREAT
      forestcurse = true if i.move==:FORESTSCURSE
      notnorm = true if i.type != (:NORMAL)
      bothimmune = false if i.move==:DESTINYBOND

      for oppmon in [@opponent, @opponent.pbPartner]
        next if oppmon.hp <= 0
        bothimmune = false if [0x05,0x06,0x017].include?(i.function) && i.basedamage==0 && (oppmon.pbCanPoison?(false,false,i.move==:TOXIC && @attacker.ability==:CORROSION) && !hydrationCheck(oppmon)) || oppmon.status == :POISON
        bothimmune = false if i.move==:PERISHSONG && !(oppmon.ability == :SOUNDPROOF && !(moldBreakerCheck(@attacker) || myceliumMightCheck(@attacker))) # Gen 9 Mod - Added myceliumMightCheck
        bothimmune = false if i.function == 0xdc && (!noLeechSeed(oppmon) || oppmon.effects[:LeechSeed] > -1)
        if i.basedamage > 0
          typemod = pbTypeModNoMessages(i.pbType(@attacker),@attacker,oppmon,i)
          typemod = 0 if oppmon.ability == :WONDERGUARD && typemod<=4
          bothimmune = false if typemod != 0
        end
      end
    end
    if bothimmune
      bothimmune = false if (tricktreat && notnorm) || forestcurse
      forcedscore+=140 if bothimmune
    end
    for i in 0...@attacker.moves.length
      next if @attacker.moves[i].nil? || !@battle.pbCanChooseMove?(@attacker.index,i,false)
      haspp = true if @attacker.moves[i].pp != 0
    end
    forcedscore+=200 if !haspp
    forcedscore+=30 if @attacker.effects[:Torment]
    if @attacker.effects[:Encore]>0
      if @opponent.hp>0
        encoreScore = @mondata.scorearray[@opponent.index][@attacker.effects[:EncoreIndex]]
      elsif @opponent.pbPartner.hp>0
        encoreScore = @mondata.scorearray[@opponent.pbPartner.index][@attacker.effects[:EncoreIndex]]
      else
        encoreScore = 100
      end
      forcedscore+=200 if encoreScore <= 30
      forcedscore+=110 if @attacker.effects[:Torment]
    end
    if @attacker.item == :CHOICEBAND || @attacker.item == :CHOICESPECS || @attacker.item == :CHOICESCARF || @attacker.ability == :GORILLATACTICS || @attacker.debutanteCheck
      if @attacker.effects[:ChoiceBand] != nil
        for i in 0...@attacker.moves.length
          if @attacker.moves[i].move == @attacker.effects[:ChoiceBand]
            choiceindex = i
            break
          end
        end
      elsif @attacker.effects[:GorillaLock] != nil
        for i in 0...@attacker.moves.length
          if @attacker.moves[i].move == @attacker.effects[:GorillaLock]
            choiceindex = i
            break
          end
        end
      end
      if choiceindex
        if @opponent.hp > 0
          choiceScore = @mondata.scorearray[@opponent.index][choiceindex]
        elsif @opponent.pbPartner.hp > 0
          choiceScore = @mondata.scorearray[@opponent.pbPartner.index][choiceindex]
        end
        forcedscore += 50 if choiceScore <= 50
        forcedscore += 130 if choiceScore <= 30
        forcedscore += 150 if choiceScore <= 10
      end
    end
    PBDebug.log(sprintf("Initial switchscore building: fsteak (%d)",forcedscore)) if $INTERNAL
    #Type effectiveness
    effcheck = PBTypes.twoTypeEff(@opponent.type1,@attacker.type1,@attacker.type2)
    if effcheck > 4
      typescore+=20
    elsif effcheck < 4
      typescore-=20
    end
    effcheck2 = PBTypes.twoTypeEff(@opponent.type2,@attacker.type1,@attacker.type2)
    if effcheck2 > 4
      typescore+=20
    elsif effcheck2 < 4
      typescore-=20
    end
    if @opponent.pbPartner.totalhp !=0
      typescore *= 0.5
      effcheck = PBTypes.twoTypeEff(@opponent.pbPartner.type1,@attacker.type1,@attacker.type2)
      if effcheck > 4
        typescore+=10
      elsif effcheck < 4
        typescore-=10
      end
      effcheck2 = PBTypes.twoTypeEff(@opponent.pbPartner.type2,@attacker.type1,@attacker.type2)
      if effcheck2 > 4
        typescore+=10
      elsif effcheck2 < 4
        typescore-=10
      end
    end
    PBDebug.log(sprintf("Initial switchscore building: Typing (%d)",typescore)) if $INTERNAL
    #Special cases
    # If the opponent just switched in to counter you
    if !@battle.doublebattle && @opponent.turncount == 0 && checkAIdamage() > @attacker.hp &&
       @attacker.hp > 0.6 * @attacker.totalhp && !notOHKO?(@attacker,@opponent,true)
      specialscore += 100
    end
    # If future sight is about to trigger
    if @attacker.effects[:FutureSight] == 1
      move, moveuser = @attacker.pbFutureSightUserPlusMove
      damage = pbRoughDamage(move,moveuser,@attacker)
      specialscore += 50 if damage > @attacker.hp
      specialscore += 50 if 2*damage > @attacker.hp
    end
    #If opponent is in a two turn attack
    if !@battle.doublebattle && @opponent.effects[:TwoTurnAttack]!=0 #this section really doesn't work in doubles.
      twoturntype = $cache.moves[@opponent.effects[:TwoTurnAttack]].type
      for i in @mondata.party
        next if i.nil? || i.hp == 0 || @mondata.party.index(i) == @attacker.pokemonIndex
        if @attacker.moves[0].pbTypeModifierNonBattler(twoturntype,@opponent,i) < 4
          specialscore += 80
          break
        end
      end
    end
    # If trainer has unburned activated
    specialscore -= 30 if @attacker.unburdened

    for oppmon in [@opponent,@opponent.pbPartner]
      next if oppmon.hp <= 0
      #Good Switch for two-turn attack
      if !pbAIfaster?(nil,nil,@attacker,oppmon) && oppmon.effects[:TwoTurnAttack]!=0
        twoturntype = $cache.moves[oppmon.effects[:TwoTurnAttack]].type
        bestmove = checkAIbestMove(oppmon)
        for i in @mondata.party
          next if i.nil? || i.hp == 0 || @mondata.party.index(i) == @attacker.pokemonIndex
          if bestmove.pbTypeModifierNonBattler(twoturntype,oppmon,i) < 4
            specialscore += 80
            specialscore += 80 if bestmove.pbTypeModifierNonBattler(twoturntype,oppmon,i) < 4
            break
          end
        end
      end
      #Getting around fake out
      if checkAImoves([:FAKEOUT],getAIMemory(oppmon)) && oppmon.turncount == 1
        for i in @mondata.party
          count+=1
          next if i.nil? || i.hp == 0 || @mondata.party.index(i) == @attacker.pokemonIndex
          if (i.ability == :STEADFAST)
            specialscore+=90
            break
          end
        end
      end
      #punishing skill-link/loaded dixe multi-hit contact moves # Gen 9 Mod - Added Loaded Dice
      if oppmon.ability == :SKILLLINK || oppmon.hasWorkingItem(:LOADEDDICE) || oppmon.ability == :TECHLINK
        if getAIMemory(oppmon).any? {|moveloop| moveloop!=nil && moveloop.function==0xC0 && moveloop.contactMove?}
          for i in @mondata.party
            next if i.nil? || i.hp == 0 || @mondata.party.index(i) == @attacker.pokemonIndex
            if (i.item == :ROCKYHELMET) || (i.ability == :ROUGHSKIN) || (i.ability == :IRONBARBS)
              specialscore+=70
              break
            end
          end
        end
      end
      #Justified switch vs dark attack moves
      bestmove=checkAIbestMove()
      if bestmove.pbType(@opponent) == :DARK && @attacker.ability != :JUSTIFIED
        for i in @mondata.party
          next if i.nil? || i.hp == 0 || @mondata.party.index(i) == @attacker.pokemonIndex
          if i.ability==:JUSTIFIED
            specialscore+=70
            break
          end
        end
      end

      #Thermal Exchange switch vs Fire attack moves
      # Gen 9 Mod - Added Thermal Exchange
      bestmove=checkAIbestMove()
      if bestmove.pbType(@opponent) == :FIRE && @attacker.ability != :THERMALEXCHANGE
        for i in @mondata.party
          next if i.nil? || i.hp == 0 || @mondata.party.index(i) == @attacker.pokemonIndex
          if i.ability==:THERMALEXCHANGE
            specialscore+=70
            break
          end
        end
      end
    end
    PBDebug.log(sprintf("Initial switchscore building: Specific Switches (%d)",specialscore)) if $INTERNAL
    switchscore = statusscore + statscore + healscore + forcedscore + typescore + specialscore
    PBDebug.log(sprintf("%s: initial switchscore: %d" ,getMonName(@attacker.species),switchscore)) if $INTERNAL
    statantiscore = 0
    specialmove = false
    physmove = false
    for i in @attacker.moves
      next if i.nil?
      specialmove = true if i.pbIsSpecial?()
      physmove = true if i.pbIsPhysical?()
    end
    if @mondata.roles.include?(:SWEEPER)
      statantiscore += (30) * @attacker.stages[PBStats::ATTACK] if @attacker.stages[PBStats::ATTACK] > 0 && physmove
      statantiscore += (30) * @attacker.stages[PBStats::SPATK] if @attacker.stages[PBStats::SPATK] > 0 && specialmove
      statantiscore += (30) * @attacker.stages[PBStats::SPEED] if @attacker.stages[PBStats::SPEED] > 0 unless (@mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL) || @mondata.roles.include?(:TANK))
      statantiscore += (30) * @attacker.effects[:FocusEnergy]
    else
      statantiscore += (15) * @attacker.stages[PBStats::ATTACK] if @attacker.stages[PBStats::ATTACK] > 0 && physmove
      statantiscore += (15) * @attacker.stages[PBStats::SPATK] if @attacker.stages[PBStats::SPATK] > 0 && specialmove
      statantiscore += (15) * @attacker.stages[PBStats::SPEED] if @attacker.stages[PBStats::SPEED] > 0 unless (@mondata.roles.include?(:PHYSICALWALL) || @mondata.roles.include?(:SPECIALWALL) || @mondata.roles.include?(:TANK))
      statantiscore += (30) * @attacker.effects[:FocusEnergy]
    end
    if @mondata.roles.include?(:PHYSICALWALL)
      statantiscore += (30) * @attacker.stages[PBStats::DEFENSE] if @attacker.stages[PBStats::DEFENSE] > 0
    else
      statantiscore += (15) * @attacker.stages[PBStats::DEFENSE] if @attacker.stages[PBStats::DEFENSE] > 0
    end
    if @mondata.roles.include?(:SPECIALWALL)
      statantiscore += (30) * @attacker.stages[PBStats::SPDEF] if @attacker.stages[PBStats::SPDEF] > 0
    else
      statantiscore += (15) * @attacker.stages[PBStats::SPDEF] if @attacker.stages[PBStats::SPDEF] > 0
    end
    statantiscore += (20) * @attacker.stages[PBStats::EVASION] if @attacker.stages[PBStats::EVASION] > 0 && !(checkAIaccuracy(aimem) || checkAIaccuracy(aimem2))
    statantiscore += 100 if @attacker.effects[:Substitute] > 0
    PBDebug.log(sprintf("Initial noswitchscore building: Stat Stages (%d)", statantiscore)) if $INTERNAL
    hazardantiscore = 0
    hazardantiscore += (15) * @attacker.pbOwnSide.effects[:Spikes]
    hazardantiscore += (15) * @attacker.pbOwnSide.effects[:ToxicSpikes]
    hazardantiscore += (15) if @attacker.pbOwnSide.effects[:StealthRock]
    hazardantiscore += (15) if @attacker.pbOwnSide.effects[:StickyWeb]
    hazardantiscore += (15) if (@attacker.pbOwnSide.effects[:StickyWeb] && @mondata.roles.include?(:SWEEPER))
    airmon = @attacker.isAirborne?
    hazarddam = totalHazardDamage(@attacker)
    if ((@attacker.hp.to_f) / @attacker.totalhp) * 100 < hazarddam
      hazardantiscore += 100
    end
    temppartyko = true
    for i in @mondata.party
      next if i.nil?
      next if i.isEgg?
      next if @mondata.party.index(i) == @attacker.pokemonIndex
      next if @mondata.partyroles[@mondata.party.find_index(i)].include?(:ACE) && hazardantiscore > 0

      i = pbMakeFakeBattler(i, @mondata.party.index(i))
      temppartyko = false if ((i.hp.to_f) / i.totalhp) * 100 > totalHazardDamage(i)
    end
    hazardantiscore += 200 if temppartyko
    PBDebug.log(sprintf("Initial noswitchscore building: Entry Hazards (%d)", hazardantiscore)) if $INTERNAL
    # Better Switching Options
    betterswitchscore = 0
    if pbAIfaster?(nil, nil, @attacker, @opponent) && pbAIfaster?(nil, nil, @attacker, @opponent.pbPartner)
      betterswitchscore += 90 if @attacker.pbHasMove?(:VOLTSWITCH) || @attacker.pbHasMove?(:UTURN) || @attacker.pbHasMove?(:FLIPTURN)
    end
    betterswitchscore += 100 if @attacker.turncount == 0
    betterswitchscore += 90 if @attacker.effects[:PerishSong] == 0 && @attacker.pbHasMove?(:BATONPASS)
    betterswitchscore += 60 if @attacker.ability == :WIMPOUT || @attacker.ability == :EMERGENCYEXIT
    PBDebug.log(sprintf("Initial noswitchscore building: Alternate Switching Options (%d)", betterswitchscore)) if $INTERNAL
    secondwindscore = 0
    # Can you kill them before they kill you?
    for oppmon in [@opponent, @opponent.pbPartner]
      next if oppmon.hp <= 0

      if !checkAIpriority()
        if pbAIfaster?(nil, nil, @attacker, oppmon)
          secondwindscore += 130 if @mondata.roughdamagearray[oppmon.index].any? { |movescore| movescore > 100 }
        end
      else
        for i in 0...@attacker.moves.length
          next if @attacker.moves[i].nil?
          next if !@attacker.moves[i].pbIsPriorityMoveAI(@attacker)

          secondwindscore += 130 if @mondata.roughdamagearray[oppmon.index][i] > 100 && pbAIfaster?(nil, nil, @attacker, oppmon)
        end
      end
    end
    monturn = (50 - (@attacker.turncount * 25))
    monturn /= 1.5 if @mondata.roles.include?(:LEAD)
    secondwindscore += monturn if monturn > 0
    PBDebug.log(sprintf("Initial noswitchscore building: Second Wind Situations (%d)", secondwindscore)) if $INTERNAL
    noswitchscore = statantiscore + hazardantiscore + betterswitchscore + secondwindscore
    noswitchscore *= 4 if @attacker.isGiga?
    noswitchscore += 999 if Reborn && !@battle.doublebattle && @battle.opponent.name == "Priscilla"
    PBDebug.log(sprintf("%s: initial noswitchscore: %d", getMonName(@attacker.species), noswitchscore)) if $INTERNAL
    finalscore = switchscore - noswitchscore
    finalscore /= 2.0 if @mondata.skill < HIGHSKILL
    finalscore -= 100 if @mondata.skill < MEDIUMSKILL
    return finalscore
  end

  def pbStatChangingSwitch(mon)
    # Sticky Web
    trainer = @battle.pbGetOwner(mon.index)
    if mon.pbOwnSide.effects[:StickyWeb] && !mon.isAirborne?
      drop = @battle.FE == :FOREST ? 2 : 1
      mon.stages[PBStats::SPEED]-= drop unless mon.item == :WHITEHERB || mon.item == :CLEARAMULET || mon.ability == :WHITESMOKE || mon.ability == :CLEARBODY || mon.item == :HEAVYDUTYBOOTS # Gen 9 Mod - Added Clear Amulet
      mon.unburdened = true         if mon.ability == :UNBURDEN && mon.item == :WHITEHERB
    end
    # Iron Ball Deep Earth
    if mon.item == :IRONBALL && @battle.FE == :DEEPEARTH
      mon.stages[PBStats::SPEED] -=2 if !(mon.ability ==:CONTRARY)
      mon.stages[PBStats::SPEED] +=2 if (mon.ability ==:CONTRARY)
    end
    # Magnet Deep Earth
    if mon.item == :MAGNET && @battle.FE == :DEEPEARTH
      if !(mon.ability ==:CONTRARY)
        mon.stages[PBStats::SPEED] -=1
        mon.stages[PBStats::SPATK] +=1
      else
        mon.stages[PBStats::SPEED] +=1
        mon.stages[PBStats::SPATK] -=1
      end
    end
    # Seed Stat boosts
    if mon.item == @battle.field.seeds[:seedtype]
      mon.unburdened = true if mon.ability == :UNBURDEN
      @battle.field.seeds[:stats].each_pair {|stat,statval| mon.stages[stat]+=statval}
    end
    # Electric Terrain instant Cellbattery
    if Rejuv && @battle.FE == :ELECTERRAIN && mon.item == :CELLBATTERY
      mon.unburdened = true if mon.ability == :UNBURDEN
      mon.stages[PBStats::ATTACK]+=1
    end
    # Abilities on Entry
    # Intrepid Sword
    if mon.ability==:INTREPIDSWORD
      boost = (@battle.FE == :FAIRYTALE || @battle.FE == :COLOSSEUM) ? 2 : 1
      mon.stages[PBStats::ATTACK]+=boost
      mon.stages[PBStats::SPATK]+=1 if (@battle.FE == :FAIRYTALE || @battle.FE == :COLOSSEUM)
    end
    # Dauntless Shield
    if mon.ability==:DAUNTLESSSHIELD
      boost = (@battle.FE == :FAIRYTALE || @battle.FE == :COLOSSEUM) ? 2 : 1
      mon.stages[PBStats::DEFENSE]+=boost
      mon.stages[PBStats::SPDEF]+=1 if (@battle.FE == :FAIRYTALE || @battle.FE == :COLOSSEUM)
    end
    # Anticipation
    if mon.ability==:ANTICIPATION
      mon.stages[PBStats::SPEED] += 1 if mon.pbAnticipationShudder
    end
    # Steadfast
    if mon.ability==:STEADFAST && ((Rejuv && @battle.FE == :ELECTERRAIN) || @battle.state.effects[:ELECTERRAIN] > 0)
      mon.stages[PBStats::SPEED]+=1
    end
    # Light Metal
    if mon.ability==:LIGHTMETAL && (@battle.FE == :DEEPEARTH)
      mon.stages[PBStats::SPEED]+=1
    end
    # Heavy Metal
    if mon.ability==:HEAVYMETAL && (@battle.FE == :DEEPEARTH)
      mon.stages[PBStats::DEFENSE]+=1
      mon.stages[PBStats::SPEED]-=1
    end
    # Lightning Rod
    if mon.ability==:LIGHTNINGROD && (Rejuv && @battle.FE == :ELECTERRAIN)
      mon.stages[PBStats::SPATK]+=1
    end
    # Magma Armor
    if mon.ability==:MAGMAARMOR && (@battle.FE == :DRAGONSDEN || @battle.FE == :VOLCANIC)
      boost = 1
      mon.stages[PBStats::DEFENSE]+=boost
      mon.stages[PBStats::SPDEF]+=boost if @battle.FE == :DRAGONSDEN
    end
    # Shell Armor
    if Rejuv && mon.ability==:SHELLARMOR && @battle.FE == :DRAGONSDEN
      mon.stages[PBStats::DEFENSE]+=1
    end
    # Stance Change
    if mon.ability==:STANCECHANGE || mon.ability==:STALL
      if ((@battle.FE == :FAIRYTALE || (Rejuv && @battle.FE == :CHESS)) && mon.ability==:STANCECHANGE) || (Rejuv && @battle.FE == :CHESS && mon.ability==:STALL)
        mon.stages[PBStats::DEFENSE]+=1
      end
    end
    # Crests
    case mon.crested
      when :VESPIQUEN
        mon.stages[PBStats::ATTACK]+=1
        mon.stages[PBStats::SPATK]+=1
      when :THIEVUL then mon.stages[PBStats::SPATK]+=1
    end
    # Fairy Tale Abilities
    if @battle.FE == :FAIRYTALE
      if [:MAGICGUARD, :MAGICBOUNCE, :POWEROFALCHEMY, :MIRRORARMOR, :PASTELVEIL].include?(mon.ability)
        mon.stages[PBStats::SPDEF]+=1
      end
      if [:BATTLEARMOR, :SHELLARMOR, :POWEROFALCHEMY].include?(mon.ability)
        mon.stages[PBStats::DEFENSE]+=1
      end
      if mon.ability == :MAGICIAN
        mon.stages[PBStats::SPATK]+=1
      end
    end
    # Starlight Illuminate
    if @battle.FE == :STARLIGHT
      mon.stages[PBStats::SPATK]+=2 if mon.ability == :ILLUMINATE
    end
    # Water Compaction
    if @battle.FE == :MISTY || @battle.FE == :CORROSIVEMIST || @battle.state.effects[:MISTY] > 0
      mon.stages[PBStats::DEFENSE]+=2 if mon.ability == :WATERCOMPACTION
    end
    # Water's Surface Abilities
    if @battle.FE == :WATERSURFACE && KAIZOMOD
      if mon.ability == :COMMANDER
        mon.stages[PBStats::ATTACK]+=1
        mon.stages[PBStats::DEFENSE]+=1
        mon.stages[PBStats::SPATK]+=1
        mon.stages[PBStats::SPDEF]+=1
        mon.stages[PBStats::SPEED]+=1
      end
    end
    # Mirror Field Evasion & Accuracy
    if @battle.FE == :MIRROR
      mon.stages[PBStats::EVASION]+=1 if [:SANDVEIL,:SNOWCLOAK,:TANGLEDFEET,:MAGICBOUNCE,:COLORCHANGE].include?(mon.ability)
      mon.stages[PBStats::EVASION]+=2 if mon.ability == :ILLUSION
      mon.stages[PBStats::ACCURACY]+=1 if [:KEENEYE,:COMPOUNDEYES].include?(mon.ability)
    end
    # Rattled
    if mon.ability == :RATTLED
      mon.stages[PBStats::SPEED]+=1 if @battle.FE == :DIMENSIONAL || @battle.FE == :FROZENDIMENSION || @battle.FE == :HAUNTED
    end
    # Psychic Terrain
    if @battle.FE == :PSYTERRAIN || @battle.state.effects[:PSYTERRAIN] > 0
      mon.stages[PBStats::SPATK]+=2 if mon.ability == :FOREWARN || mon.ability == :ANTICIPATION
    end
    # Dimensionals
    if @battle.FE == :DIMENSIONAL || @battle.FE == :FROZENDIMENSION
      mon.stages[PBStats::SPATK]+=1 if mon.ability == :BERSERK
      mon.stages[PBStats::ATTACK]+=1 if mon.ability == :JUSTIFIED || mon.ability == :ANGERPOINT
      # if mon.ability == :ANGERSHELL && KAIZOMOD # Gen 9 Mod - Added Anger Shell / On base mod, it isn't affected by the field
      #  mon.stages[PBStats::ATTACK]+=1
      #  mon.stages[PBStats::DEFENSE]-=1
      #  mon.stages[PBStats::SPATK]+=1
      #  mon.stages[PBStats::SPDEF]-=1
      #  mon.stages[PBStats::SPEED]+=1
      # end
    end
    # Sky
    if @battle.FE == :SKY
      mon.stages[PBStats::DEFENSE]+=1 if mon.ability == :BIGPECKS
      mon.stages[PBStats::SPEED]+=1 if mon.ability == :LEVITATE || mon.ability == :SOLARIDOL || mon.ability == :LUNARIDOL
    end
    # Infernal
    if @battle.FE == :INFERNAL
      mon.stages[PBStats::DEFENSE]+=1 if mon.ability == :MAGMAARMOR || mon.ability == :FLAMEBODY || mon.ability == :DESOLATELAND
      mon.stages[PBStats::SPDEF]+=1 if mon.ability == :MAGMAARMOR || mon.ability == :FLAMEBODY || mon.ability == :DESOLATELAND
    end
    # Colosseum
    if @battle.FE == :COLOSSEUM
      mon.stages[PBStats::DEFENSE]+=1 if  (mon.ability == :BATTLEARMOR || mon.ability == :SHELLARMOR)
      mon.stages[PBStats::SPDEF]+=1 if  (mon.ability == :MIRRORARMOR || mon.ability == :MAGICGUARD)
      mon.stages[PBStats::ATTACK]+=1 if mon.ability == :JUSTIFIED || mon.ability == :NOGUARD
      mon.stages[PBStats::SPATK]+=1 if mon.ability == :JUSTIFIED || mon.ability == :NOGUARD
    end
    # Concert
    if @battle.ProgressiveFieldCheck(PBFields::CONCERT)
      mon.stages[PBStats::DEFENSE]+=1 if [:HEAVYMETAL,:SOLIDROCK,:PUNKROCK,:SOUNDPROOF,:ROCKHEAD].include?(mon.ability)
      if  @battle.ProgressiveFieldCheck(PBFields::CONCERT,2,4)
        mon.stages[PBStats::SPEED]+=1 if mon.ability == :EMERGENCYEXIT || mon.ability == :RUNAWAY
        if  @battle.ProgressiveFieldCheck(PBFields::CONCERT,3,4)
          mon.stages[PBStats::SPEED]+=2 if mon.ability == :RATTLED
        end
      end
    end
    if @battle.FE == :BACKALLEY
      mon.stages[PBStats::DEFENSE]+=1 if  mon.ability == :ANTICIPATION || mon.ability == :FOREWARN
      mon.stages[PBStats::SPDEF]+=1 if  mon.ability == :ANTICIPATION || mon.ability == :FOREWARN
      mon.stages[PBStats::ATTACK]+=1 if mon.ability == :PICKPOCKET || mon.ability == :MERCILESS
      mon.stages[PBStats::SPATK]+=1 if mon.ability == :MAGICIAN
    end
    if @battle.FE == :CITY
      mon.stages[PBStats::DEFENSE]+=1 if  mon.ability == :BIGPECKS
      mon.stages[PBStats::ATTACK]+=1 if mon.ability == :EARLYBIRD
      mon.stages[PBStats::SPEED]+=1 if mon.ability == :PICKUP || mon.ability == :RATTLED
    end
    #Contrary
    if mon.ability==:CONTRARY
      for stage in 0...mon.stages.length
        next if mon.stages[stage].nil?
        mon.stages[stage] = -1*mon.stages[stage]
      end
    end
  end

  def shouldHardSwitch?(attacker, switch_in_index)
    for i in 0...attacker.moves.length
      return true if !@battle.pbCanChooseMove?(attacker.index, i, false)
    end
    return true if attacker.effects[:PerishSong] > 0
    switch_in = pbMakeFakeBattler(@battle.pbParty(attacker.index)[switch_in_index], switch_in_index)
    opponent = firstOpponent()
    return true if (!$cache.moves[opponent.lastMoveUsed].nil? && $cache.moves[opponent.lastMoveUsed].category == :status)

    # check if the switch_in would just straight up die from assumed move used
    assumed_damage = 0
    assumed_damage += totalHazardDamage(switch_in) * switch_in.totalhp / 100
    assumed_move = checkAIbestMove(opponent, attacker)
    assumed_damage = pbRoughDamage(assumed_move, @opponent, switch_in)

    return false if assumed_damage > switch_in.hp

    switch_in.hp -= assumed_damage
    return false if !canKillBeforeOpponentKills?(switch_in, opponent)

    return true
  end

  def canKillBeforeOpponentKills?(attacker,opponent)
    #first check what move is fastest for attacker and opponent
    attmovearray, attdamagearray = checkAIMovePlusDamage(attacker,opponent,wholearray: true)
    oppmovearray, oppdamagearray = checkAIMovePlusDamage(opponent,attacker,wholearray: true)
    attdamagearray.map! {|score| score > 0 && notOHKO?(attacker,opponent,true) ? score-1 : score }
    oppdamagearray.map! {|score| score > 0 && notOHKO?(opponent,attacker,true) ? score-1 : score }

    #filter out all moves that actually kill
    attmovearray.filter!.with_index {|move, index| attdamagearray[index] >= opponent.hp }
    oppmovearray.filter!.with_index {|move, index| oppdamagearray[index] >= attacker.hp }
    attdamagearray.filter! {|score| score >= opponent.hp }
    oppdamagearray.filter! {|score| score >= attacker.hp }
    return true if oppmovearray.length==0
    return false if attmovearray.length==0

    #check if there are any moves the attacker has that would move before all moves of opponent
    return attmovearray.any? {|attmove| oppmovearray.all? {|oppmove| pbAIfaster?(attmove,oppmove,attacker,opponent) } }
  end


  ################################################################################
  # AI Memory utility functions
  ################################################################################

  def addMoveToMemory(battler, move)
    return if move.nil?

    trainer = @battle.pbGetOwner(battler.index)
    return if !trainer # wild battle
    return if !battler.pokemon

    # check if pokemon is added to trainer array, add if isn't the case
    @aiMoveMemory[trainer][battler.pokemon.personalID] = [] if !@aiMoveMemory[trainer].key?(battler.pokemon.personalID)
    knownmoves = @aiMoveMemory[trainer][battler.pokemon.personalID]
    knownmoves.filter! { |moveloop| moveloop != nil && moveloop.move != move.move } # remove old instance of the same move

    # update the move memory by taking current known move array and add new move in array form to it
    @aiMoveMemory[trainer][battler.pokemon.personalID] = knownmoves.push(move)
  end

  def addMonToMemory(pkmn, index)
    trainer = @battle.pbGetOwner(index)
    return if !trainer # wild battle

    @aiMoveMemory[trainer][pkmn.personalID] = [] if !@aiMoveMemory[trainer].key?(pkmn.personalID)
  end

  def getAIMemory(battler = @opponent, inspecting = false)
    return [] if !battler || battler.hp == 0

    trainer = @battle.pbGetOwner(battler.index)
    return [] if !trainer

    if (@mondata.index == battler.index || @mondata.index == battler.pbPartner.index) && battler.is_a?(PokeBattle_Battler) && inspecting != true
      # we're checking out own moves stupid
      ret = @mondata.index == battler.index ? battler.moves : battler.pbPartner.moves
      return ret.find_all { |moveloop| moveloop.move }
    elsif battler.is_a?(PokeBattle_Battler) || inspecting == true
      # we're dealing with enemy battler
      if @aiMoveMemory[trainer][battler.pokemon.personalID]
        return @aiMoveMemory[trainer][battler.pokemon.personalID]
      else
        return []
      end
    elsif battler.is_a?(PokeBattle_Pokemon)
      # we're dealing with mon not on field
      for key in @aiMoveMemory.keys
        return @aiMoveMemory[key][battler.personalID] if @aiMoveMemory[key].key?(battler.personalID)
      end
      return []
    end
  end

  def getAIKnownParty(battler)
    trainer = @battle.pbGetOwner(battler.index)
    return [] if !trainer

    party = @battle.pbPartySingleOwner(battler.index)
    knownparty = party.find_all { |mon| mon.hp > 0 && @aiMoveMemory[trainer].keys.include?(mon.personalID) }
    return knownparty
  end

  def checkAImovesAllOpponents(moveID)
    return checkAImoves(moveID) || checkAImoves(moveID, battler: @opponent.pbPartner)
  end

  def checkAImoves(moveID, memory = nil, battler: @opponent)
    memory = getAIMemory(battler) if memory.nil?
    # basic "does the other mon have x"
    for i in moveID
      for j in memory
        move = pbChangeMove(j, battler)
        return true if i == move.move # i should already be an ID here
      end
    end
    return false
  end

  def checkAIhealing(memory = nil)
    memory = getAIMemory(@opponent) if memory.nil?
    # less basic "can the other mon heal"
    for j in memory
      return true if j.isHealingMove?
    end
    return false
  end

  def checkAIpriority(memory = nil)
    opp = memory.nil? ? @opponent : nil
    memory = getAIMemory(@opponent) if memory.nil?
    # "does the other mon have priority"
    for j in memory
      if opp
        return true if j.pbIsPriorityMoveAI(opp)
      else
        return true if j.priority > 0
      end
    end
    return false
  end

  def checkAIaccuracy(memory = nil)
    memory = getAIMemory(@opponent) if memory.nil?
    # "does the other mon have moves that don't miss"
    for j in memory
      move = pbChangeMove(j, @opponent)
      return true if move.accuracy == 0 && move.function != 0x111 # Exclude Future Sight and Doom Desire
    end
    return false
  end

  def checkAIMovePlusDamage(opponent = @opponent, attacker = @attacker, memory = nil, wholearray: false)
    # Opponent is the one attacking, bit confusing i know
    return [[], []] if wholearray && (!opponent || opponent.hp == 0)
    return [PokeBattle_Struggle.new(@battle, nil, nil), 0] if !opponent || opponent.hp == 0

    memory = getAIMemory(opponent) if memory.nil?
    damagearray = []
    movearray = []
    if @mondata.skill >= HIGHSKILL && memory.length < opponent.moves.count { |move| !move.nil? }
      unless memory.any? { |moveloop| moveloop != nil && moveloop.pbType(opponent) == opponent.type1 && moveloop.betterCategory != :status }
        stabmove1 = PokeBattle_Move_FFF.new(@battle, opponent, opponent.type1)
        damagearray.push(pbRoughDamage(stabmove1, opponent, attacker))
        movearray.push(stabmove1)
      end
      unless memory.any? { |moveloop| moveloop != nil && moveloop.pbType(opponent) == opponent.type2 && moveloop.betterCategory != :status } || opponent.type2.nil?
        stabmove2 = PokeBattle_Move_FFF.new(@battle, opponent, opponent.type2)
        damagearray.push(pbRoughDamage(stabmove2, opponent, attacker))
        movearray.push(stabmove2)
      end
    end
    for j in memory
      damagearray.push(pbRoughDamage(j, opponent, attacker))
      movearray.push(j)
    end
    return [movearray, damagearray] if wholearray
    return [PokeBattle_Struggle.new(@battle, nil, nil), 0] if damagearray.empty?

    return [movearray[damagearray.index(damagearray.max)], damagearray.max]
  end

  def checkAIdamage(attacker = @attacker, opponent = @opponent, memory = nil)
    bestmove, damage = checkAIMovePlusDamage(opponent, attacker, memory)
    return damage
  end

  def checkAIbestMove(opponent = @opponent, attacker = @attacker, memory = nil)
    bestmove, damage = checkAIMovePlusDamage(opponent, attacker, memory)
    return bestmove
  end

  ######################################################
  # AI Damage Calc
  ######################################################
  def pbRoughDamage(move = @move, attacker = @attacker, opponent = @opponent)
    return 0 if opponent.species == 0 || attacker.species == 0
    return 0 if opponent.hp == 0 || attacker.hp == 0
    return 0 if move.pp == 0 && !move.zmove && move.type != :SHADOW

    oldmove = move
    move = pbChangeMove(move, attacker)
    basedamage = move.basedamage
    return 0 if !move.basedamage || move.basedamage == 0

    typemod = pbTypeModNoMessages(move.type, attacker, opponent, move)
    typemod = pbTypeModNoMessages(move.pbType(attacker), attacker, opponent, move) if @mondata.skill >= HIGHSKILL
    return typemod if typemod <= 0
    return 0 if !moveSuccesful?(oldmove, attacker, opponent)
    return 0 if opponent.totalhp == 1 && (opponent.ability == :STURDY || (opponent.ability == :STALWART && @battle.FE == :COLOSSEUM)) && move.pbNumHits(attacker) == 1 && !attacker.effects[:ParentalBond] && !attacker.effects[:TyphBond] && !move.pbIsMultiHit && !moldBreakerCheck(attacker)

    if @mondata.skill >= MEDIUMSKILL
      basedamage = pbBetterBaseDamage(move, attacker, opponent)
    end
    return 0 if move.zmove && ((opponent.effects[:Disguise] || (opponent.effects[:IceFace] && (move.pbIsPhysical? || @battle.FE == :FROZENDIMENSION))) && !moldBreakerCheck(opponent))
    return basedamage if (0x6A..0x73).include?(move.function) || [0xD4, 0xE1].include?(move.function) # fixed damage function codes (sonicboom, etc)

    basedamage *= 1.25 if (attacker.effects[:ParentalBond] || attacker.effects[:TyphBond]) && move.pbNumHits(attacker) == 1
    basedamage *= 4 if attacker.crested == :LEDIAN && move.punchMove?
    if attacker.crested == :CINCCINO && !move.pbIsMultiHit
      basedamage *= 0.3
      if attacker.ability == :SKILLLINK || attacker.ability == :TECHLINK
        basedamage *= 5
      else
        basedamage = (basedamage * 19 / 6).floor
      end
    end
    # Gen 9 Mod - Moves will deal twice as much damage if the opponent last used Glaive Rush and we can act before them
    # i.e. we can use our move before they use their next move and remove the Glaive Rush effect.
    if opponent.effects[:GlaiveRush] && pbAIfaster?(move,nil,attacker,opponent)
      basedamage*=2
    end
    fielddata = @battle.field.moveData(move.move)
    type=move.type

    # Determine if an AI mon is attacking a player mon
    ai_mon_attacking = false
    if attacker.index == 2 && !@battle.pbOwnedByPlayer?(attacker.index)
      ai_mon_attacking = true if opponent.index==1 || opponent.index==3
    elsif opponent.index==0 || opponent.index==2
      ai_mon_attacking = true
    end

    # More accurate move type (includes Normalize, most type-changing moves, etc.)
    if @mondata.skill >= MINIMUMSKILL
      type = move.pbType(attacker, type)
    end
    oppitemworks = opponent.itemWorks?
    attitemworks = attacker.itemWorks?

    # ATTACKING/BASE DAMAGE SECTION
    atk = attacker.attack
    atk = attacker.spatk if attacker.crested == :REUNICLUS && attacker.type1 == :PSYCHIC && move.pbIsPhysical?(type)
    atkstage = attacker.stages[PBStats::ATTACK] + 6
    if attacker.species == :AEGISLASH
      originalform = attacker.form
      dummymon = pbAegislashStats(attacker)
      dummymon.pbUpdate
      atk = dummymon.attack
      atkstage = dummymon.stages[PBStats::ATTACK] + 6
      dummymon.form = originalform
      dummymon.pbUpdate
    end
    if move.function == 0x309 || move.function == 0x20D || move.function == 0x80A || move.function == 0x80B # Shell Side Arm / Super Ultra Mega Death Move / Unleashed Power / Blinding Speed
      move.smartDamageCategory(attacker, opponent)
    end
    if move.function == 0x121 # Foul Play
      atk = opponent.attack
      atkstage = opponent.stages[PBStats::ATTACK] + 6
    end
    if move.pbIsSpecial?(type)
      atk = attacker.spatk
      atk = attacker.attack if attacker.crested == :REUNICLUS && attacker.type1 == :FIGHTING
      atkstage = attacker.stages[PBStats::SPATK] + 6
      if attacker.species == :AEGISLASH
        originalform = attacker.form
        dummymon = pbAegislashStats(attacker)
        dummymon.pbUpdate
        atk = dummymon.spatk
        atkstage = dummymon.stages[PBStats::SPATK] + 6
        dummymon.form = originalform
        dummymon.pbUpdate
      end
      if move.function == 0x121 # Foul Play
        atk = opponent.spatk
        atkstage = opponent.stages[PBStats::SPATK] + 6
      end
      if @battle.FE == :GLITCH
        atk = attacker.getSpecialStat(opponent.ability == :UNAWARE)
        atkstage = 6 # getspecialstat handles unaware
      end
    end
    case attacker.crested
      when :CLAYDOL then atkstage = attacker.stages[PBStats::DEFENSE] + 6 if move.pbIsSpecial?(type)
      when :DEDENNE then atkstage = attacker.stages[PBStats::SPEED] + 6 if !move.pbIsSpecial?(type)
    end
    if opponent.ability != :UNAWARE || moldBreakerCheck(attacker)
      atk = (atk * PBStats::StageMul[atkstage]).floor
    end
    if @mondata.skill >= BESTSKILL && @battle.FE != :INDOOR
      basedamage = (basedamage * move.moveFieldBoost).round
      case @battle.FE
        when :ELECTERRAIN
          if type == :GROUND && opponent.ability == :TRANSISTOR
            basedamage = (basedamage * 0.5).round
          end
          if Rejuv && type == :ELECTRIC && attacker.ability == :TERAVOLT
            basedamage = (basedamage * 1.5).round
          end
        when :CHESS
          # Chess Move boost
          if CHESSMOVES.include?(move.move)
            if (opponent.ability == :ADAPTABILITY) || (opponent.ability == :ANTICIPATION) || (opponent.ability == :SYNCHRONIZE) || (opponent.ability == :TELEPATHY)
              basedamage = (basedamage * 0.5).round
            end
            if (opponent.ability == :OBLIVIOUS) || (opponent.ability == :KLUTZ) || (opponent.ability == :UNAWARE) || (opponent.ability == :SIMPLE) || (Rejuv && opponent.ability == :DEFEATIST) || opponent.effects[:Confusion] > 0
              basedamage = (basedamage * 2).round
            end
            if Rejuv && (attacker.ability == :KLUTZ)
              basedamage = 0
            end
          end
          if Rejuv && attacker.ability == :RECKLESS || attacker.ability == :GORILLATACTICS
            basedamage = (basedamage * 1.2).round
          end
          # Illusion damage boost TODO?: make sure the AI doesn't see this for opposing Zoroark?
          if Rejuv && attacker.effects[:Illusion]
            basedamage = (basedamage * 1.2).round
          end
          if Rejuv && attacker.ability == :COMPETITIVE
            frac = (1.0 * attacker.hp) / (1.0 * attacker.totalhp)
            multiplier = 1.0
            multiplier += ((1.0 - frac) / 0.8)
            if frac < 0.2
              multiplier = 2.0
            end
            basedamage = (basedamage * multiplier).round
          end
          # Queen piece boost
          if attacker.pokemon.piece == :QUEEN && attacker.ability != :QUEENLYMAJESTY
            basedamage = (basedamage * 1.5).round
          end

          # Knight piece boost
          if attacker.pokemon.piece == :KNIGHT && opponent.pokemon.piece == :QUEEN
            basedamage = (basedamage * 3.0).round
          end
        when :BIGTOP
          if (type == :FIGHTING && move.pbIsPhysical?(type)) || STRIKERMOVES.include?(move.move)
            if attacker.ability == :HUGEPOWER || attacker.ability == :GUTS ||
               attacker.ability == :PUREPOWER || attacker.ability == :SHEERFORCE
              provimult = 2.2
              provimult = 1.6 if $game_variables[:DifficultyModes] == 1
              provimult = ((provimult - 1.0) * 2.0) + 1.0 if $game_switches[:FieldFrenzy]
              basedamage = (basedamage * provimult).round
            else
              provimult = 1.2
              provimult = 1.1 if $game_variables[:DifficultyModes] == 1
              provimult = ((provimult - 1.0) * 2.0) + 1.0 if $game_switches[:FieldFrenzy]
              basedamage = (basedamage * provimult).round
            end
          end
          if move.isSoundBased?
            provimult = 1.5
            provimult = 1.25 if $game_variables[:DifficultyModes] == 1
            provimult = ((provimult - 1.0) * 2.0) + 1.0 if $game_switches[:FieldFrenzy]
            basedamage = (basedamage * provimult).round
          end
        when :SHORTCIRCUIT
          if type == :ELECTRIC
            damageroll = @battle.field.getRoll(update_roll: false, maximize_roll: (@battle.state.effects[:ELECTERRAIN] > 0))
            damageroll = ((damageroll - 1.0) / 2.0) + 1.0 if $game_variables[:DifficultyModes] == 1 && !$game_switches[:FieldFrenzy]
            damageroll = ((damageroll - 1.0) * 2.0) + 1.0 if $game_variables[:DifficultyModes] != 1 && $game_switches[:FieldFrenzy] && damageroll > 1
            damageroll = damageroll / 2.0 if $game_variables[:DifficultyModes] != 1 && $game_switches[:FieldFrenzy] && damageroll < 1
            basedamage = (basedamage * damageroll).round
          end
        when :WATERSURFACE, :UNDERWATER
          if attacker.ability == :PROPELLERTAIL
            basedamage = (basedamage * 1.5).round if move.priority > 0
          end
        when :CAVE
          if move.isSoundBased?
            provimult = 1.5
            provimult = 1.25 if $game_variables[:DifficultyModes] == 1
            provimult = ((provimult - 1.0) * 2.0) + 1.0 if $game_switches[:FieldFrenzy]
            basedamage = (basedamage * provimult).round
          end
        when :MOUNTAIN
          if PBFields::WINDMOVES.include?(move.move) && @battle.pbWeather == :STRONGWINDS
            provimult = 1.5
            provimult = 1.25 if $game_variables[:DifficultyModes] == 1
            provimult = ((provimult - 1.0) * 2.0) + 1.0 if $game_switches[:FieldFrenzy]
            basedamage = (basedamage * provimult).round
          end
        when :SNOWYMOUNTAIN
          if PBFields::WINDMOVES.include?(move.move) && @battle.pbWeather == :STRONGWINDS
            provimult = 1.5
            provimult = 1.25 if $game_variables[:DifficultyModes] == 1
            provimult = ((provimult - 1.0) * 2.0) + 1.0 if $game_switches[:FieldFrenzy]
            basedamage = (basedamage * provimult).round
          end
        when :MIRROR
          if PBFields::MIRRORMOVES.include?(move.move) && opponent.stages[PBStats::EVASION] > 0
            provimult = 2.0
            provimult = 1.5 if $game_variables[:DifficultyModes] == 1
            provimult = ((provimult - 1.0) * 2.0) + 1.0 if $game_switches[:FieldFrenzy]
            basedamage = (basedamage * provimult).round
          end
        when :CORRUPTED
          if attacker.ability == :CORROSION
            basedamage = (basedamage * 1.5).round
          end
        when :CONCERT1, :CONCERT2, :CONCERT3, :CONCERT4
          if move.isSoundBased?
            provimult = 1.5
            provimult = 1.25 if $game_variables[:DifficultyModes] == 1
            provimult = ((provimult - 1.0) * 2.0) + 1.0 if $game_switches[:FieldFrenzy]
            basedamage = (basedamage * provimult).round
          end
        when :DEEPEARTH
          if type == :GROUND && opponent.hasType?(:GROUND)
            provimult = 0.5
            provimult = 0.75 if $game_variables[:DifficultyModes] == 1 && !$game_switches[:FieldFrenzy]
            provimult = 0.25 if $game_variables[:DifficultyModes] != 1 && $game_switches[:FieldFrenzy]
            basedamage = (basedamage * provimult).round
          end
          if move.pbIsPriorityMoveAI(attacker) && move.basedamage > 0
            provimult = 0.7
            provimult = 0.85 if $game_variables[:DifficultyModes] == 1
            provimult = ((provimult - 1.0) * 2.0) + 1.0 if $game_switches[:FieldFrenzy]
            basedamage = (basedamage * provimult).round
          end
          if move.pbIsPriorityMoveAI(attacker) && move.basedamage > 0
            provimult = 1.3
            provimult = 1.15 if $game_variables[:DifficultyModes] == 1
            provimult = ((provimult - 1.0) * 2.0) + 1.0 if $game_switches[:FieldFrenzy]
            basedamage = (basedamage * provimult).round
          end
      end
    end
    if type == :POISON && (opponent.ability == :PASTELVEIL || opponent.pbPartner.ability == :PASTELVEIL) && ([:MISTY, :RAINBOW].include?(@battle.FE) || @battle.state.effects[:MISTY] > 0)
      basedamage = (basedamage * 0.5).round
    end
    for terrain in [:ELECTERRAIN, :GRASSY, :MISTY, :PSYTERRAIN]
      if @battle.state.effects[terrain] > 0
        overlaymult = move.moveOverlayBoost(terrain)
        basedamage *= overlaymult
      end
    end

    if @mondata.skill >= MEDIUMSKILL
      ############ ATTACKER ABILITY CHECKS ############
      case attacker.ability
        when :TECHNICIAN then basedamage = (basedamage * 1.5).round if (basedamage <= 60) || ([:FACTORY, :CONCERT1, :CONCERT2, :CONCERT3, :CONCERT4].include?(@battle.FE) && basedamage <= 80)
        when :TECHLINK then basedamage = (basedamage * 1.5).round if (basedamage <= 60) || ([:FACTORY, :CONCERT1, :CONCERT2, :CONCERT3, :CONCERT4].include?(@battle.FE) && basedamage <= 80)
        when :IRONFIST then basedamage = (basedamage * 1.2).round if move.punchMove?
        when :STRONGJAW then basedamage = (basedamage * 1.5).round if PBStuff::BITEMOVE.include?(move.move)
        when :SHARPNESS then basedamage = (basedamage * 1.5).round if move.sharpMove?
        when :TRUESHOT then basedamage = (basedamage * 1.3).round if PBStuff::BULLETMOVE.include?(move.move)
        when :TOUGHCLAWS then basedamage = (basedamage * 1.3).round if move.contactMove?
        when :RECKLESS then basedamage = (basedamage * 1.2).round if move.recoil > 0 || [0x130, 0x10B, 0x506].include?(move.function) # Shadow End, High Jump Kick, Axe Kick
        when :FLAREBOOST then basedamage = (basedamage * 1.5).round if (attacker.status == :BURN || [:BURNING, :VOLCANIC, :INFERNAL].include?(@battle.FE)) && move.pbIsSpecial?(type) && @battle.FE != :FROZENDIMENSION
        when :TOXICBOOST
          if (attacker.status == :POISON || @battle.FE == :CORROSIVE || @battle.FE == :CORROSIVEMIST || @battle.FE == :WASTELAND || @battle.FE == :MURKWATERSURFACE) && move.pbIsPhysical?(type)
            basedamage = @battle.FE == :CORRUPTED ? (basedamage * 2.0).round : (basedamage * 1.5).round
          end
        when :RIVALRY
          if attacker.gender != 2 && opponent.gender != 2
            if attacker.gender == opponent.gender
              basedamage = (basedamage * 1.25).round
            else
              basedamage = (basedamage * 0.75).round
            end
          end
        when :MEGALAUNCHER then basedamage = (basedamage * 1.5).round if [:AURASPHERE, :DRAGONPULSE, :DARKPULSE, :WATERPULSE, :ORIGINPULSE, :TERRAINPULSE].include?(move.move)
        when :SANDFORCE
          if @battle.pbWeather == :SANDSTORM && (type == :ROCK || type == :GROUND || type == :STEEL)
            basedamage = (basedamage * 1.3).round
          elsif @mondata.skill >= BESTSKILL && (@battle.FE == :DESERT || @battle.FE == :ASHENBEACH) && (type == :ROCK || type == :GROUND || type == :STEEL)
            basedamage = (basedamage * 1.3).round
          end
        when :ANALYTIC then basedamage = (basedamage * 1.3).round if pbAIfaster?(move, nil, attacker, opponent)
        when :SHEERFORCE then basedamage = (basedamage * 1.3).round if move.effect > 0
        when :NORMALIZE then basedamage = (basedamage * 1.5).round
        when :HUSTLE then atk = [:BACKALLEY, :CITY].include?(@battle.FE) ? (atk * 1.75).round : (atk * 1.5).round if move.pbIsPhysical?(type)
        when :GUTS then atk = (atk * 1.5).round if !attacker.status.nil? && move.pbIsPhysical?(type)
        when :PLUS, :MINUS
          if move.pbIsSpecial?(type)
            partner = attacker.pbPartner
            if partner.ability == :PLUS || partner.ability == :MINUS
              atk = (atk * 1.5).round
            elsif (@battle.FE == :SHORTCIRCUIT || (Rejuv && @battle.FE == :ELECTERRAIN) || @battle.state.effects[:ELECTERRAIN] > 0) && @mondata.skill >= BESTSKILL
              atk = (atk * 1.5).round
            end
          end
        when :DEFEATIST then atk = (atk * 0.5).round if attacker.hp <= (attacker.totalhp / 2.0).floor
        when :PUREPOWER, :HUGEPOWER
          if @mondata.skill >= BESTSKILL
            if attacker.ability == :PUREPOWER && (@battle.FE == :PSYTERRAIN || @battle.state.effects[:PSYTERRAIN] > 0)
              atk = (atk * 2.0).round if move.pbIsSpecial?(type)
            else
              atk = (atk * 2.0).round if move.pbIsPhysical?(type)
            end
          elsif move.pbIsPhysical?(type)
            atk = (atk * 2.0).round
          end
        when :SOLARPOWER then atk = (atk * 1.5).round if @battle.pbWeather == :SUNNYDAY && move.pbIsSpecial?(type)
        when :SLOWSTART then atk = (atk * 0.5).round if attacker.turncount < 5 && move.pbIsPhysical?(type)
        when :PUNKROCK, :LIQUIDVOICE
          basedamage = [:BIGTOP,:CAVE].include?(@battle.FE) ? (basedamage * 1.5).round : (basedamage * 1.3).round if move.isSoundBased?
        # only check attacker ability here, partner ability is checked seperately
        when :STEELYSPIRIT then basedamage = @battle.FE == :FAIRYTALE ? (basedamage * 2.0).round : (basedamage * 1.5).round if type == :STEEL
        when :STEELWORKER then basedamage = @battle.FE == :FACTORY ? (basedamage * 2.0).round : (basedamage * 1.5).round if type == :STEEL
        when :TRANSISTOR then basedamage = (basedamage * 1.5).round if type == :ELECTRIC
        when :DRAGONSMAW then basedamage = (basedamage * 1.5).round if type == :DRAGON
        when :WATERBUBBLE then basedamage = (basedamage * 2.0).round if type == :WATER
        when :INEXORABLE then basedamage = (basedamage * 1.5).round if pbAIfaster?(move, nil, attacker, opponent) && type == :DRAGON
        when :GORILLATACTICS then atk = (atk * 1.5).round if move.pbIsPhysical?(type)
        when :FLOWERGIFT
          # only check attacker ability here, partner ability is checked seperately
          if attacker.species == :CHERRIM && (@battle.pbWeather == :SUNNYDAY || @battle.FE == :BEWITCHED || @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN) || attacker.crested == :CHERRIM) && move.pbIsPhysical?(type)
            atk = (atk * 1.5).round
          end
        when :QUARKDRIVE then basedamage = (basedamage * 1.3).round if (attacker.effects[:Quarkdrive][0] == PBStats::ATTACK && move.pbIsPhysical?(type)) || (attacker.effects[:Quarkdrive][0] == PBStats::SPATK && move.pbIsSpecial?(type))
        # Gen 9 Mod - Prothosynthesis
        when :PROTOSYNTHESIS then basedamage = (basedamage * 1.3).round if (attacker.effects[:Protosynthesis][0] == PBStats::ATTACK && move.pbIsPhysical?(type)) || (attacker.effects[:Protosynthesis][0] == PBStats::SPATK && move.pbIsSpecial?(type))
        # Gen 9 Mod - Hadron Engine
        when :HADRONENGINE
          if ((@battle.FE == :ELECTERRAIN || @battle.state.effects[:ELECTERRAIN] > 0) && move.pbIsSpecial?(type)) &&  @battle.FE != :FROZENDIMENSION
            basedamage=(basedamage*((5461/4096.to_f))).round
          end
        # Gen 9 Mod - Orichalcum Pulse
        when :ORICHALCUMPULSE
          if (@battle.pbWeather== :SUNNYDAY && move.pbIsPhysical?(type)) && @battle.FE != :FROZENDIMENSION
            basedamage=(basedamage*((5461/4096.to_f))).round
          end
        # Execution
        when :EXECUTION then basedamage = (basedamage * 2.0).round if opponent.hp <= (opponent.totalhp / 2.0).floor
        # Solar Idol
        when :SOLARIDOL
          if type == :FIRE
            basedamage = (basedamage * 1.5).round
          end
          if @battle.pbWeather == :SUNNYDAY && move.pbIsPhysical?(type)
            atk = (atk * 1.5).round
          end
        # Solar Idol
        when :LUNARIDOL
          if type == :ICE
            basedamage = (basedamage * 1.5).round
          end
          if @battle.pbWeather == :HAIL && move.pbIsSpecial?(type)
            atk = (atk * 1.5).round
          end
        when :AERILATE then basedamage = [:MOUNTAIN, :SNOWYMOUNTAIN, :SKY].include?(@battle.FE) ? (basedamage * 1.5).round : (basedamage * 1.3).round if move.type == :NORMAL
        when :GALVANIZE
          if move.type == :NORMAL
            if @battle.FE == :ELECTERRAIN || @battle.FE == :FACTORY || @battle.state.effects[:ELECTERRAIN] > 0 # Electric or Factory Fields
              basedamage = (basedamage * 1.5).round
            elsif @battle.FE == :SHORTCIRCUIT # Short-Circuit Field
              basedamage = (basedamage * 2).round
            else
              basedamage = (basedamage * 1.3).round
            end
          end
        when :PIXILATE
          if move.type == :NORMAL
            if @battle.FE == :MISTY || @battle.state.effects[:MISTY] > 0
              basedamage = (basedamage * 1.5).round # Misty Field
            else
              basedamage = (basedamage * 1.3).round
            end
          end
        when :IMMOLATE
          if move.type == :NORMAL
            if @battle.FE == :INFERNAL
              basedamage = (basedamage * 1.5).round # Misty Field
            else
              basedamage = (basedamage * 1.3).round
            end
          end
        when :REFRIGERATE then basedamage = [:ICY, :SNOWYMOUNTAIN, :FROZENDIMENSION].include?(@battle.FE) ? (basedamage * 1.5).round : (basedamage * 1.3).round if move.type == :NORMAL
        when :DUSKILATE then basedamage = (basedamage * 1.3).round if move.type == :NORMAL
      end

      # Gen 9 Mod - Beads of Ruin, Sword of Ruin
      ruinmult = (@battle.FE == :FROZENDIMENSION || @battle.FE == :DIMENSONAL) && !KAIZOMOD ? 0.67 : 0.75
      if (attacker.pbOpposing1.ability == :VESSELOFRUIN || attacker.pbOpposing2.ability == :VESSELOFRUIN || attacker.pbPartner.ability == :VESSELOFRUIN) && attacker.ability != :VESSELOFRUIN && move.pbIsSpecial?(type)
        basedamage=(basedamage*ruinmult).round
      elsif (attacker.pbOpposing1.ability == :TABLETSOFRUIN || attacker.pbOpposing2.ability == :TABLETSOFRUIN || attacker.pbPartner.ability == :TABLETSOFRUIN) && attacker.ability != :TABLETSOFRUIN && move.pbIsPhysical?(type)
        basedamage=(basedamage*ruinmult).round
      end

      ############ PARTNER ABILITY CHECKS ############
      case attacker.pbPartner.ability
        when :POWERSPOT then basedamage = [:HOLY, :PSYTERRAIN, :HAUNTED, :BEWITCHED].include?(@battle.FE) ? (basedamage * 1.5).round : (basedamage * 1.3).round
        # Steely Spirit does not stack if user AND partner have the ability
        when :STEELYSPIRIT then basedamage = @battle.FE == :FAIRYTALE ? (basedamage * 2.0).round : (basedamage * 1.5).round if type == :STEEL && attacker.ability != :STEELYSPIRIT
        when :BATTERY then atk = (Rejuv && @battle.FE == :ELECTERRAIN) ? (atk * 1.5).round : (atk * 1.3).round if move.pbIsSpecial?(type)
        when :FLOWERGIFT
          # only check partner here, attacker has been checked earlier
          if attacker.pbPartner.species == :CHERRIM && (@battle.pbWeather == :SUNNYDAY || @battle.FE == :BEWITCHED || @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN) || attacker.pbPartner.crested == :CHERRIM) && move.pbIsPhysical?(type)
            atk = (atk * 1.5).round
          end
      end

      ############ OPPONENT ABILITY CHECKS ############
      if !moldBreakerCheck(attacker)
        case opponent.ability
          when :HEATPROOF then basedamage = (basedamage * 0.5).round if type == :FIRE
          when :DRYSKIN then basedamage = (basedamage * 1.25).round if type == :FIRE
          when :THICKFAT then atk = (atk * 0.5).round if type == :ICE || type == :FIRE
          when :PUNKROCK then basedamage = (basedamage * 0.5).round if move.isSoundBased?
        end
      end

      ############ ATTACKER ITEM CHECKS ############
      if attitemworks # don't bother with this if it doesn't work
        # Type-boosting items
        case type
          when :NORMAL
            case attacker.item
              # Gen 9 Mod - Blank Plate added.
              when :SILKSCARF, :BLANKPLATE then basedamage = (basedamage * 1.2).round
              when :NORMALGEM then basedamage = (basedamage * 1.3).round
            end
          when :FIGHTING
            case attacker.item
              when :BLACKBELT, :FISTPLATE then basedamage = (basedamage * 1.2).round
              when :FIGHTINGGEM then basedamage = (basedamage * 1.3).round
            end
          when :FLYING
            case attacker.item
              when :SHARPBEAK, :SKYPLATE then basedamage = (basedamage * 1.2).round
              when :FLYINGGEM then basedamage = (basedamage * 1.3).round
            end
          when :POISON
            case attacker.item
              when :POISONBARB, :TOXICPLATE then basedamage = (basedamage * 1.2).round
              when :FLYINGGEM then basedamage = (basedamage * 1.3).round
            end
          when :GROUND
            case attacker.item
              when :SOFTSAND, :EARTHPLATE then basedamage = (basedamage * 1.2).round
              when :GROUNDGEM then basedamage = (basedamage * 1.3).round
            end
          when :ROCK
            case attacker.item
              when :HARDSTONE, :STONEPLATE, :ROCKINCENSE then basedamage = (basedamage * 1.2).round
              when :ROCKGEM then basedamage = (basedamage * 1.3).round
            end
          when :BUG
            case attacker.item
              when :SILVERPOWDER, :INSECTPLATE then basedamage = (basedamage * 1.2).round
              when :BUGGEM then basedamage = (basedamage * 1.3).round
            end
          when :GHOST
            case attacker.item
              when :SPELLTAG, :SPOOKYPLATE then basedamage = (basedamage * 1.2).round
              when :GHOSTGEM then basedamage = (basedamage * 1.3).round
            end
          when :STEEL
            case attacker.item
              when :METALCOAT, :IRONPLATE then basedamage = (basedamage * 1.2).round
              when :STEELGEM then basedamage = (basedamage * 1.3).round
            end
          when :FIRE
            case attacker.item
              when :CHARCOAL, :FLAMEPLATE then basedamage = (basedamage * 1.2).round
              when :FIREGEM then basedamage = (basedamage * 1.3).round
            end
          when :WATER
            case attacker.item
              when :MYSTICWATER, :SPLASHPLATE, :SEAINCENSE, :WAVEINCENSE then basedamage = (basedamage * 1.2).round
              when :WATERGEM then basedamage = (basedamage * 1.3).round
            end
          when :GRASS
            case attacker.item
              when :MIRACLESEED, :MEADOWPLATE, :ROSEINCENSE then basedamage = (basedamage * 1.2).round
              when :FLYINGGEM then basedamage = (basedamage * 1.3).round
            end
          when :ELECTRIC
            case attacker.item
              when :MAGNET, :ZAPPLATE then basedamage = (basedamage * 1.2).round
              when :ELECTRICGEM then basedamage = (basedamage * 1.3).round
            end
          when :PSYCHIC
            case attacker.item
              when :TWISTEDSPOON, :MINDPLATE, :ODDINCENSE then basedamage = (basedamage * 1.2).round
              when :PSYCHICGEM then basedamage = (basedamage * 1.3).round
            end
          when :ICE
            case attacker.item
              when :NEVERMELTICE, :ICICLEPLATE then basedamage = (basedamage * 1.2).round
              when :ICEGEM then basedamage = (basedamage * 1.3).round
            end
          when :DRAGON
            case attacker.item
              when :DRAGONFANG, :DRACOPLATE then basedamage = (basedamage * 1.2).round
              when :DRAGONGEM then basedamage = (basedamage * 1.3).round
            end
          when :DARK
            case attacker.item
              when :BLACKGLASSES, :DREADPLATE then basedamage = (basedamage * 1.2).round
              when :DARKGEM then basedamage = (basedamage * 1.3).round
            end
          when :FAIRY
            case attacker.item
              # Gen 9 Mod - Added Fairy Feather
              when :FAIRYFEATHER,:PIXIEPLATE then basedamage = (basedamage * 1.2).round
              when :FAIRYGEM then basedamage = (basedamage * 1.3).round
            end
        end
        # Muscle Band
        if attacker.item == :MUSCLEBAND && move.pbIsPhysical?(type)
          basedamage = (basedamage * 1.1).round
        # Wise Glasses
        elsif attacker.item == :WISEGLASSES && move.pbIsSpecial?(type)
          basedamage = (basedamage * 1.1).round
        # Legendary Orbs
        elsif attacker.item == :LUSTROUSORB
          if attacker.pokemon.species == :PALKIA && (type == :DRAGON || type == :WATER)
            basedamage = (basedamage * 1.2).round
          end
        elsif attacker.item == :ADAMANTORB
          if attacker.pokemon.species == :DIALGA && (type == :DRAGON || type == :STEEL)
            basedamage = (basedamage * 1.2).round
          end
        elsif attacker.item == :GRISEOUSORB
          if attacker.pokemon.species == :GIRATINA && (type == :DRAGON || type == :GHOST)
            basedamage = (basedamage * 1.2).round
          end
        elsif attacker.item == :SOULDEW
          if (attacker.pokemon.species == :LATIAS || attacker.pokemon.species == :LATIOS) &&
             (type == :DRAGON || type == :PSYCHIC)
            basedamage = (basedamage * 1.2).round
          end
        # Gen 9 Mod - Ogerpon's Masks give it a 1.2x boost to all damaging moves it uses.
        elsif (attacker.item == :WELLSPRINGMASK || attacker.item == :HEARTHFLAMEMASK || attacker.item == :CORNERSTONEMASK)
          if (attacker.pokemon.species == :OGERPON)
            basedamage = (basedamage*1.2).round
          end
        # Gen 9 Mod - Added Punching Glove
        elsif (attacker.item == :PUNCHINGGLOVE)
          basedamage = (basedamage*1.1).round if move.punchMove?
        elsif attacker.crested
          if attacker.crested == :FERALIGATR
            basedamage = (basedamage * 1.5).round if PBStuff::BITEMOVE.include?(move.move)
          elsif attacker.crested == :BOLTUND
            basedamage = (basedamage * 1.5).round if PBStuff::BITEMOVE.include?(move.move) && pbAIfaster?(move, nil, attacker, opponent)
          elsif attacker.crested == :CLAYDOL
            basedamage = (basedamage * 1.5).round if move.isBeamMove?
          elsif attacker.crested == :DRUDDIGON
            basedamage = (basedamage * 1.3).round if type == :DRAGON || type == :FIRE
          elsif attacker.crested == :FEAROW
            basedamage = (basedamage * 1.5).round if PBStuff::STABBINGMOVE.include?(move.move)
          elsif attacker.crested == :DUSKNOIR
            basedamage = (basedamage * 1.5).round if move.basedamage <= 60 || ((@battle.FE == :FACTORY || @battle.ProgressiveFieldCheck(PBFields::CONCERT)) && move.basedamage <= 80)
          elsif attacker.crested == :CRABOMINABLE
            basedamage = (basedamage * 1.5).round if !pbAIfaster?()
          elsif attacker.crested == :AMPHAROS
            basedamage = attacker.hasType?(type) ? (basedamage * 1.2).round : (basedamage * 1.5).round if attacker.moves[0] == move
          elsif attacker.crested == :CASTFORM && attacker.form == 1
            basedamage = (basedamage * 1.5).round if @battle.pbWeather == :SUNNYDAY && move.pbIsSpecial?(type)
          elsif attacker.crested == :LUXRAY
            basedamage = (basedamage * 1.2).round if move.type == :NORMAL && type == :ELECTRIC
          elsif attacker.crested == :SAWSBUCK
            case attacker.form
              when 0 then basedamage *= 1.2 if move.type == :NORMAL && type == :WATER
              when 1 then basedamage *= 1.2 if move.type == :NORMAL && type == :FIRE
              when 2 then basedamage *= 1.2 if move.type == :NORMAL && type == :GROUND
              when 3 then basedamage *= 1.2 if move.type == :NORMAL && type == :ICE
            end
          elsif attacker.crested == :EMBOAR
            basedamage *= (2 * (attacker.hp * 1.0 / attacker.totalhp))
          end
        end
      end
      #pbBaseDamageMultiplier

      ############ MISC CHECKS ############
      # Charge
      # Gen 9 Mod - Charge lasts until the user uses an electric move.
      if attacker.effects[:Charge] == true && type == :ELECTRIC
        basedamage = (basedamage*2.0).round
      end
      # Helping Hand
      if attacker.effects[:HelpingHand]
        basedamage = (basedamage * 1.5).round
      end
      # Flash Fire
      if attacker.effects[:FlashFire] && type == :FIRE
        atk = (atk * 1.5).round
      end
      # Water/Mud Sport
      if type == :FIRE
        if @battle.state.effects[:WaterSport] > 0
          basedamage = (basedamage * 0.33).round
        end
      elsif type == :ELECTRIC
        if @battle.state.effects[:MudSport] > 0
          basedamage = (basedamage * 0.33).round
        end
      # Dark Aura/Aurabreak
      elsif type == :DARK
        if @battle.battlers.any? { |battler| battler.ability == :DARKAURA }
          if @battle.FE == :DARKNESS1
            basedamage *= @battle.battlers.any? { |battler| battler.ability == :AURABREAK } ? 0.6 : 1.4
          elsif @battle.FE == :DARKNESS2
            basedamage *= @battle.battlers.any? { |battler| battler.ability == :AURABREAK } ? 0.5 : 1.5
          elsif @battle.FE == :DARKNESS3
            basedamage *= @battle.battlers.any? { |battler| battler.ability == :AURABREAK } ? 0.33 : 1.66
          else
            basedamage *= @battle.battlers.any? { |battler| battler.ability == :AURABREAK } ? 2.0 / 3 : 4.0 / 3
          end
        end
      # Fairy Aura/Aurabreak
      elsif type == :FAIRY
        if @battle.battlers.any? { |battler| battler.ability == :FAIRYAURA }
          if @battle.FE == :DARKNESS1
            basedamage *= @battle.battlers.any? { |battler| battler.ability == :AURABREAK } ? 0.7 : 1.3
          elsif @battle.FE == :DARKNESS2
            basedamage *= @battle.battlers.any? { |battler| battler.ability == :AURABREAK } ? 0.8 : 1.2
          elsif @battle.FE == :DARKNESS3
            basedamage *= @battle.battlers.any? { |battler| battler.ability == :AURABREAK } ? 0.9 : 1.1
          else
            basedamage *= @battle.battlers.any? { |battler| battler.ability == :AURABREAK } ? 2.0 / 3 : 4.0 / 3
          end
        end
      end
      # Spiritomb Crest
      if attacker.crested == :SPIRITOMB
        atk = (atk * (1.0 + (attacker.pbFaintedPokemonCount * 0.2))).round
      end
      # Gen 9 Mod - Added Supreme Overlord
      if attacker.ability == :SUPREMEOVERLORD # Gen 9 Mod - Added Supreme Overlord
        atk = (atk * (1.0 + (attacker.pbFaintedPokemonCount * 0.1))).round
      end
    end

    # Pinch Abilities
    if @mondata.skill >= BESTSKILL
      if ([:BURNING, :VOLCANIC, :INFERNAL].include?(@battle.FE) || attacker.effects[:Blazed]) && attacker.ability == :BLAZE && type == :FIRE
        atk = (atk * 1.5).round
      elsif @battle.FE == :FOREST && attacker.ability == :OVERGROW && type == :GRASS
        atk = (atk * 1.5).round
      elsif Rejuv && @battle.FE == :GRASSY && attacker.ability == :OVERGROW && type == :GRASS
        atk = (atk * 1.5).round
      # elsif @battle.FE == :FOREST && attacker.ability == :SWARM && type == :BUG && !KAIZOMOD
      #   atk = (atk * 1.5).round
      elsif ((@battle.FE == :WATERSURFACE && !attacker.isAirborne?) || @battle.FE == :UNDERWATER) && attacker.ability == :TORRENT && type == :WATER
        atk = (atk * 1.5).round
      elsif @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN) && attacker.ability == :SWARM && type == :BUG
        atk = (atk * 1.5).round if @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN, 1, 2)
        atk = (atk * 1.8).round if @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN, 3, 4)
        atk = (atk * 2).round if @battle.FE == :FLOWERGARDEN5
      elsif @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN) && attacker.ability == :OVERGROW && type == :GRASS
        atk = (atk * 1.5).round if @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN, 1, 2)
        atk = (atk * 1.8).round if @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN, 3, 4)
        atk = (atk * 2).round if @battle.FE == :FLOWERGARDEN5
      elsif attacker.hp <= (attacker.totalhp / 2.0).floor
        if (attacker.ability == :OVERGROW && type == :GRASS) || (attacker.ability == :BLAZE && type == :FIRE && @battle.FE != :FROZENDIMENSION) ||
           (attacker.ability == :TORRENT && type == :WATER) || (attacker.ability == :SWARM && type == :BUG)
          atk = (atk * 1.5).round
        end
      end
    elsif @mondata.skill >= MEDIUMSKILL && attacker.hp <= (attacker.totalhp / 2.0).floor
      if (attacker.ability == :OVERGROW && type == :GRASS) || (attacker.ability == :BLAZE && type == :FIRE) ||
         (attacker.ability == :TORRENT && type == :WATER) || (attacker.ability == :SWARM && type == :BUG)
        atk = (atk * 1.5).round
      end
    end

    # Attack-boosting items
    if @mondata.skill >= HIGHSKILL
      if attitemworks && attacker.item == :THICKCLUB
        if (attacker.pokemon.species == :CUBONE || attacker.pokemon.species == :MAROWAK) && move.pbIsPhysical?(type)
          atk = (atk * 2.0).round
        end
      elsif attitemworks && attacker.item == :DEEPSEATOOTH
        if attacker.pokemon.species == :CLAMPERL && move.pbIsSpecial?(type)
          atk = (atk * 2.0).round
        end
      elsif attitemworks && attacker.item == :LIGHTBALL
        if attacker.pokemon.species == :PIKACHU
          atk = (atk * 2.0).round
        end
      elsif (attitemworks && attacker.item == :CHOICEBAND) && move.pbIsPhysical?(type)
        atk = (atk * 1.5).round
      elsif (attitemworks && attacker.item == :CHOICESPECS) && move.pbIsSpecial?(type)
        atk = (atk * 1.5).round
      end
    end

    # Specific ability field boosts
    if @mondata.skill >= BESTSKILL
      if @battle.FE == :STARLIGHT || @battle.FE == :NEWWORLD
        atk = (atk * 1.5).round if attacker.ability == :VICTORYSTAR
        partner = attacker.pbPartner
        atk = (atk * 1.5).round if partner && partner.ability == :VICTORYSTAR
      end
      atk = (atk * 1.5).round if attacker.ability == :QUEENLYMAJESTY && (@battle.FE == :CHESS || @battle.FE == :FAIRYTALE)
      atk = (atk * 1.5).round if attacker.ability == :LONGREACH && [:MOUNTAIN, :SNOWYMOUNTAIN, :SKY].include?(@battle.FE)
      atk = (atk * 1.5).round if attacker.ability == :CORROSION && (@battle.FE == :CORROSIVE || @battle.FE == :CORROSIVEMIST)
      atk = (atk * 0.5).round if @battle.FE == :UNDERWATER && move.pbIsPhysical?(type) && type != :WATER && attacker.ability != :STEELWORKER
      atk = (atk * 1.2).round if @battle.FE == :COLOSSEUM && (move.function == 0xC0 || move.function == 0x307 || (attacker.crested == :CINCCINO && !move.pbIsMultiHit))
    end

    # Get base defense stat
    defense = opponent.defense
    defstage = opponent.stages[PBStats::DEFENSE] + 6
    applysandstorm = false
    if move.pbHitsSpecialStat?(type)
      defense = opponent.spdef
      defstage = opponent.stages[PBStats::SPDEF] + 6
      applysandstorm = true
      if @battle.FE == :GLITCH
        defense = opponent.getSpecialStat(attacker.ability == :UNAWARE)
        defstage = 6 # getspecialstat handles unaware
        applysandstorm = false # getSpecialStat handles sand
      end
    end
    defstage = 6 if move.function == 0xA9 # Chip Away (ignore stat stages)
    defstage = 6 if attacker.ability == :UNAWARE
    defense = (defense * PBStats::StageMul[defstage]).floor
    defense = 1 if (defense == 0 || !defense)

    # Glitch Item and Ability Checks
    if @mondata.skill >= HIGHSKILL && @battle.FE == :GLITCH
      if move.function == 0xE0 # Explosion
        defense = (defense * 0.5).round
      end
    end
    defense = (defense * 0.5).round if attacker.crested == :ELECTRODE && move.pbHitsPhysicalStat?(type)
    if @mondata.skill >= MEDIUMSKILL
      # Sandstorm weather
      if @battle.pbWeather == :SANDSTORM
        defense = (defense * 1.5).round if opponent.hasType?(:ROCK) && applysandstorm
      end
      # Defensive Abilities
      if opponent.ability == :MARVELSCALE
        if move.pbIsPhysical?(type)
          if !opponent.status.nil?
            defense = (defense * 1.5).round
          elsif ([:MISTY, :RAINBOW, :FAIRYTALE, :DRAGONSDEN, :STARLIGHT].include?(@battle.FE) || @battle.state.effects[:MISTY] > 0) && @mondata.skill >= BESTSKILL
            defense = (defense * 1.5).round
          end
        end
      elsif opponent.ability == :GRASSPELT
        defense = (defense * 1.5).round if move.pbIsPhysical?(type) && (@battle.FE == :GRASSY || @battle.FE == :FOREST || @battle.state.effects[:GRASSY] > 0) # Grassy Field
      elsif opponent.ability == :FLUFFY && !moldBreakerCheck(attacker)
        defense = (defense * 2).round if !move.zmove && move.contactMove? && attacker.ability != :LONGREACH
        defense = (defense * 0.5).round if type == :FIRE
      elsif opponent.ability == :FURCOAT
        defense = (defense * 2).round if move.pbIsPhysical?(type) && !moldBreakerCheck(attacker)
      elsif opponent.ability == :ICESCALES
        defense = (defense * 2).round if move.pbIsSpecial?(type) && !moldBreakerCheck(attacker)
      elsif opponent.ability == :QUARKDRIVE
        ddefense = (defense * 1.3).round if (opponent.effects[:Quarkdrive][0] == PBStats::DEFENSE && move.pbIsPhysical?(type)) || (opponent.effects[:Quarkdrive][0] == PBStats::SPDEF && move.pbIsSpecial?(type))
      # Gen 9 Mod - Added Protosynthesis
      elsif opponent.ability == :PROTOSYNTHESIS
        defense = (defense * 1.3).round if (opponent.effects[:Protosynthesis][0] == PBStats::DEFENSE && move.pbIsPhysical?(type)) || (opponent.effects[:Protosynthesis][0] == PBStats::SPDEF && move.pbIsSpecial?(type))
      # Gen 9 Mod - Beads of Ruin, Sword of Ruin
      ruinmult = (@battle.FE == :FROZENDIMENSION || @battle.FE == :DIMENSONAL) && !KAIZOMOD ? 0.67 : 0.75
      elsif ((opponent.pbOpposing1.ability == :SWORDOFRUIN || opponent.pbOpposing2.ability == :SWORDOFRUIN || opponent.pbPartner.ability == :SWORDOFRUIN) && opponent.ability != :SWORDOFRUIN)
        if @battle.state.effects[:WonderRoom] != 0 && move.pbIsSpecial?(type)
          defense = (defense * ruinmult).round
        elsif @battle.state.effects[:WonderRoom] == 0 && move.pbIsPhysical?(type)
          defense = (defense * ruinmult).round
        end
      elsif ((opponent.pbOpposing1.ability == :BEADSOFRUIN || opponent.pbOpposing2.ability == :BEADSOFRUIN || opponent.pbPartner.ability == :BEADSOFRUIN) && opponent.ability != :BEADSOFRUIN)
        if @battle.state.effects[:WonderRoom] != 0 && move.pbIsPhysical?(type)
          defense = (defense * ruinmult).round
        elsif @battle.state.effects[:WonderRoom] == 0 && move.pbIsSpecial?(type)
          defense = (defense * ruinmult).round
        end
      end
      if (@battle.pbWeather == :SUNNYDAY || @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN) || @battle.FE == :BEWITCHED || attacker.crested == :CHERRIM || attacker.pbPartner.crested == :CHERRIM) && move.pbIsSpecial?(type) && @battle.FE != :GLITCH
        defense = (defense * 1.5).round if opponent.ability == :FLOWERGIFT && (opponent.species == :CHERRIM)
        defense = (defense * 1.5).round if opponent.pbPartner.ability == :FLOWERGIFT && opponent.pbPartner.species == :CHERRIM
      end
    end

    # Field Effect defense boost
    if @mondata.skill >= BESTSKILL
      defense = (defense * move.fieldDefenseBoost(type, opponent)).round
    end

    # Defense-boosting items
    if @mondata.skill >= HIGHSKILL && @battle.FE != 24 && oppitemworks
      case opponent.item
        when :EVIOLITE
          evos = pbGetEvolvedFormData(opponent.pokemon.species, opponent.pokemon)
          defense = (defense * 1.5).round if evos && evos.length > 0
        when :ASSAULTVEST
          defense = (defense * 1.5).round if move.pbIsSpecial?(type)
        when :DEEPSEASCALE
          defense = (defense * 2.0).round if opponent.pokemon.species == :CLAMPERL && move.pbIsSpecial?(type)
        when :METALPOWDER
          defense = (defense * 2.0).round if opponent.pokemon.species == :DITTO && !opponent.effects[:Transform] && move.pbIsPhysical?(type)
        # when :EEVIUMZ
        # defense=(defense*1.5).round if opponent.pokemon.species == :EEVEE
        when :PIKANIUMZ
          defense = (defense * 1.5).round if opponent.pokemon.species == :PIKACHU
        when :LIGHTBALL
          defense = (defense * 1.5).round if opponent.pokemon.species == :PIKACHU
      end
    end

    # Main damage calculation
    damage = (((2.0 * attacker.level / 5 + 2).floor * basedamage * atk / defense).floor / 50).floor + 2 if basedamage >= 0

    # Multi-targeting attacks
    if @mondata.skill >= MEDIUMSKILL
      if move.pbTargetsAll?(attacker)
        damage = (damage * 0.75).round
      end
    end
    # Field Boosts
    if @mondata.skill >= BESTSKILL
      # Type-based field boosts
      fieldBoost = move.typeFieldBoost(type, attacker, opponent)
      overlayBoost, overlay = move.typeOverlayBoost(type, attacker, opponent)
      if fieldBoost != 1 || overlayBoost != 1
        if fieldBoost > 1 && overlayBoost > 1
          boost = [fieldBoost, overlayBoost].max
          if $game_variables[:DifficultyModes] == 1 && !$game_switches[:FieldFrenzy]
            boost = 1.25 if boost < 1.25
          elsif $game_variables[:DifficultyModes] != 1 && $game_switches[:FieldFrenzy]
            boost = 2.0 if boost < 2.0
          else
            boost = 1.5 if boost < 1.5
          end
        else
          boost = fieldBoost * overlayBoost
        end
        damage = (damage * boost).floor
      end
      case @battle.FE
        when :MOUNTAIN # Mountain
          if type == :FLYING && !move.pbIsPhysical?(type) && @battle.pbWeather == :STRONGWINDS
            provimult = 1.5
            provimult = 1.25 if $game_variables[:DifficultyModes] == 1
            provimult = ((provimult - 1.0) * 2.0) + 1.0 if $game_switches[:FieldFrenzy]
            damage = (damage * provimult).round
          end
        when :SNOWYMOUNTAIN # Snowy Mountain
          if type == :FLYING && !move.pbIsPhysical?(type) && @battle.pbWeather == :STRONGWINDS
            provimult = 1.5
            provimult = 1.25 if $game_variables[:DifficultyModes] == 1
            provimult = ((provimult - 1.0) * 2.0) + 1.0 if $game_switches[:FieldFrenzy]
            damage = (damage * provimult).round
          end
      end
      # Boosts caused by transformations
      fieldmove = @battle.field.moveData(move.move)
      if fieldmove && fieldmove[:fieldchange]
        handled = fieldmove[:condition] ? eval(fieldmove[:condition]) : true
        if handled # don't continue if conditions to change are not met
          provimult = 1.3
          provimult = 1.15 if $game_variables[:DifficultyModes] == 1
          provimult = ((provimult - 1.0) * 2.0) + 1.0 if $game_switches[:FieldFrenzy]
          damage = (damage * provimult).floor if damage >= 0
        end
      end
    end
    # Weather
    if @mondata.skill >= MEDIUMSKILL
      case @battle.pbWeather
        when :SUNNYDAY
          if @battle.state.effects[:HarshSunlight] && type == :WATER
            damage = 0
          end
          if type == :FIRE
            damage = (damage * 1.5).round
          elsif type == :WATER
            # Gen 9 Mod - Hydro Steam damage gets boosted in Sun instead of reduced.
            if move.move == :HYDROSTEAM
              damage = (damage * 1.5).round
            else
              damage = (damage * 0.5).round
            end
          end
        when :RAINDANCE
          if @battle.state.effects[:HeavyRain] && type == :FIRE
            damage = 0
          end
          if type == :FIRE
            damage = (damage * 0.5).round
          elsif type == :WATER
            damage = (damage * 1.5).round
          end
      end
    end
    if ai_mon_attacking
      random = 100
      random = 93 if @mondata.skill >= HIGHSKILL
      random = 85 if @mondata.skill >= BESTSKILL # This is something that could be tweaked based on skill
      random = 93 if $game_switches[:No_Damage_Rolls] # damage rolls
      random = 85 if @mondata.skill >= BESTSKILL && @battle.FE == :CONCERT1
      random = 100 if @mondata.skill >= BESTSKILL && @battle.FE == :CONCERT4
      damage = (damage * random / 100.0).floor
    end
    # STAB
    typecrest = false
    case attacker.crested
      when :EMPOLEON then typecrest = true if type == :ICE
      when :LUXRAY then typecrest = true if type == :DARK
      when :SAMUROTT then typecrest = true if type == :FIGHTING
      when :SIMISEAR then typecrest = true if type == :WATER
      when :SIMIPOUR then typecrest = true if type == :GRASS
      when :SIMISAGE then typecrest = true if type == :FIRE
      when :GOTHITELLE then typecrest = true if type == :PSYCHIC || type == :DARK
      when :REUNICLUS then typecrest = true if type == :PSYCHIC || type == :FIGHTING
      when :ZOROARK
        party = @battle.pbParty(attacker.index)
        party = party.find_all { |item| item && !item.egg? && item.hp > 0 }
        if party[party.length - 1] != attacker.pokemon
          typecrest = true if party[party.length - 1].hasType?(type)
        end
    end
    if @mondata.skill>=MEDIUMSKILL
      # Water Bubble
      if attacker.ability == :WATERBUBBLE && type == :WATER
        damage=(damage*=2).round
      end
      if (attacker.hasType?(type) && (!attacker.effects[:DesertsMark])) || attacker.ability == :PROTEAN || attacker.ability == :LIBERO || typecrest==true
        if attacker.ability == :ADAPTABILITY ||
          # Gen 9 Mod - Mega (Terastalized) Ogerpon gets a Tera Boost on it's STAB moves based on it's mask.
          (((attacker.ability == :EMBODYASPECTTEAL && type == :GRASS) ||
          (attacker.ability == :EMBODYASPECTWELLSPRING && type == :WATER) ||
          (attacker.ability == :EMBODYASPECTHEARTHFLAME && type == :FIRE) ||
          (attacker.ability == :EMBODYASPECTCORNERSTONE && type == :ROCK)) && attacker.species == :OGERPON)
          damage=(damage*2).round
        else
          damage=(damage*1.5).round
        end
        if attacker.crested == :SILVALLY
          damage=(damage*1.2).round
        end
      elsif attacker.ability == :STEELWORKER && type == :STEEL
        if @battle.FE == :FACTORY # Factory Field
          damage=(damage*2).round
        else
          damage=(damage*1.5).round
        end
      elsif (attacker.ability == :SOLARIDOL && type == :FIRE) || (attacker.ability == :LUNARIDOL && type == :ICE)
        damage=(damage*1.5).round
      # Gen 9 Mod - Rocky Payload
      elsif attacker.ability == :ROCKYPAYLOAD && type == :ROCK
        damage=(damage*1.5).round
      # Gen 9 Mod - Mega (Terastalized) Ogerpon still get's STAB on it's grass type moves.
      elsif (((attacker.ability == :EMBODYASPECTWELLSPRING) || (attacker.ability == :EMBODYASPECTHEARTHFLAME) || (attacker.ability == :EMBODYASPECTCORNERSTONE)) && type == :GRASS)
        damage=(damage*1.5).round
      # Gen 9 Mod - Moves of each type used by Mega (Terastalized) Terapagos will get a boost.
      elsif (attacker.species == :TERAPAGOS && attacker.form ==2)
        # Gen 9 Mod - Normal moves will get 2x boost (this includes STAB).
        if (type == :NORMAL)
          damage=(damage*2).round
        # Gen 9 Mod - Moves of other types will get a 1.2x boost.
        else
          damage=(damage*1.2).round
        end
      end
    end
    # Type effectiveness
    # typemod calc has been moved to the beginning
    if @mondata.skill>=MINIMUMSKILL
        damage=(damage*typemod/4.0).round
    end
    # Water Bubble
    if @mondata.skill>=MEDIUMSKILL
      if opponent.ability == :WATERBUBBLE && type == :FIRE
        damage=(damage*=0.5).round
      end
      # Burn
      if attacker.status== :BURN && move.pbIsPhysical?(type) &&
        attacker.ability != :GUTS && move.move != :FACADE
        damage=(damage*0.5).round
      end
    end
    # Gen 9 Mod - Added Well-Baked Body
    if @mondata.skill>=MEDIUMSKILL
      if opponent.ability == :WELLBAKEDBODY && type == :FIRE
        damage*=0
      end
    end
    # Gen 9 Mod - Added Wind Rider
    if @mondata.skill>=MEDIUMSKILL
      if opponent.ability == :WINDRIDER && move.windMove?
        damage*=0
      end
    end
    # Gen 9 Mod - Added Purifying Salt
    if @mondata.skill>=MEDIUMSKILL
      if opponent.ability == :PURIFYINGSALT && type == :GHOST
        damage=(damage*0.5).round
      end
    end
    # Shelter
    if @mondata.skill>=MEDIUMSKILL
      addedtypes=move.getSecondaryType(attacker)
      if opponent.effects[:Shelter] && @battle.FE != :INDOOR && (type == @battle.field.mimicry || (!addedtypes.nil? && addedtypes.include?(@battle.field.mimicry)))
        damage=(damage*0.5).round
      end
    end
    # Screens
    if @mondata.skill>=HIGHSKILL
      if move.pbIsPhysical?(type)
        if opponent.pbOwnSide.screenActive?(:physical)
          if !opponent.pbPartner.isFainted?
            damage=(damage*0.66).round
          else
            damage=(damage*0.5).round
          end
        end
      elsif move.pbIsSpecial?(type)
        if opponent.pbOwnSide.screenActive?(:special)
          if !opponent.pbPartner.isFainted?
            damage=(damage*0.66).round
          else
            damage=(damage*0.5).round
          end
        end
      end
    end

    if @mondata.skill>=MEDIUMSKILL
      if (opponent.ability == :MULTISCALE || opponent.ability == :TERASHELL) && !moldBreakerCheck(attacker) || opponent.ability == :SHADOWSHIELD # Gen 9 Mod - Tera Shell same consideration as Multiscale
        damage=(damage*0.5).round if opponent.hp==opponent.totalhp || (opponent.ability == :SHADOWSHIELD && @battle.FE == :DIMENSIONAL)
      end
      if opponent.ability == :SOLIDROCK || opponent.ability == :FILTER || opponent.ability == :PRISMARMOR
        damage=(damage*0.75).round if typemod>4
      end
      if opponent.ability == :SHADOWSHIELD && [:STARLIGHT, :NEWWORLD, :DARKCRYSTALCAVERN].include?(@battle.FE)
        damage=(damage*0.75).round if typemod>4
      end
      if opponent.ability == :SHADOWSHIELD && @battle.ProgressiveFieldCheck(PBFields::DARKNESS,2,3)
        damage=(damage*0.33).round if opponent.hp==opponent.totalhp
      end
      damage=(damage*0.75).round if opponent.pbPartner.ability == :FRIENDGUARD
      damage=(damage*2.0).round if attacker.ability == :STAKEOUT && @battle.switchedOut[opponent.index]
      # Tinted Lens
      damage=(damage*2.0).round if attacker.ability == :TINTEDLENS && typemod<4
      # Neuroforce
      damage=(damage*1.25).round if attacker.ability == :NEUROFORCE && typemod>4
      # Meganium Crest
      damage=(damage*0.8).round if (opponent.crested == :MEGANIUM || opponent.pbPartner.crested == :MEGANIUM)
      # Beheeyem Crest
      damage=(damage*0.67).round if (opponent.crested == :BEHEEYEM) && (!opponent.hasMovedThisRound? || @battle.switchedOut[opponent.index])
      # Seviper Crest
      if attacker.crested == :SEVIPER
        multiplier = 0.5*(opponent.pokemon.hp*1.0)/(opponent.pokemon.totalhp*1.0)
        multiplier += 1.0
        damage=(damage*multiplier)
      end
    end

    # Flower Veil + Flower Garden Shenanigans
    if @mondata.skill>=BESTSKILL
      if @battle.ProgressiveFieldCheck(PBFields::FLOWERGARDEN,3,5)
        if (opponent.pbPartner.ability == :FLOWERVEIL &&
        opponent.hasType?(:GRASS)) || opponent.ability == :FLOWERVEIL
          damage=(damage*0.5).round
        end
        case @battle.FE
          when :FLOWERGARDEN3 then damage=(damage*0.75).round if opponent.hasType?(:GRASS)
          when :FLOWERGARDEN4 then damage=(damage*0.67).round if opponent.hasType?(:GRASS)
          when :FLOWERGARDEN5 then damage=(damage*0.5).round if opponent.hasType?(:GRASS)
        end
      end
    end
    # Final damage-altering items
    if @mondata.skill>=HIGHSKILL
      if (attitemworks && (attacker.item == :METRONOME || @battle.FE == :CONCERT4))
        if attacker.effects[:Metronome]>4
          damage=(damage*2.0).round
        else
          met=1.0+attacker.effects[:Metronome]*0.2
          damage=(damage*met).round
        end
      elsif (attitemworks && attacker.item == :EXPERTBELT) && typemod>4
        damage=(damage*1.2).round
      elsif (attitemworks && attacker.item == :LIFEORB)
        damage=(damage*1.3).round
      end
      if typemod>4 && oppitemworks && !ai_mon_attacking
        berrymod = opponent.ability == :RIPEN ? 0.25 : 0.5
        case opponent.item
          when :CHOPLEBERRY  then damage=(damage*berrymod).round if type == :FIGHTING
          when :COBABERRY    then damage=(damage*berrymod).round if type == :FLYING
          when :KEBIABERRY  then damage=(damage*berrymod).round if type == :POISON
          when :SHUCABERRY  then damage=(damage*berrymod).round if type == :GROUND
          when :CHARTIBERRY   then damage=(damage*berrymod).round if type == :ROCK
          when :TANGABERRY  then damage=(damage*berrymod).round if type == :BUG
          when :KASIBBERRY  then damage=(damage*berrymod).round if type == :GHOST
          when :BABIRIBERRY   then damage=(damage*berrymod).round if type == :STEEL
          when :OCCABERRY   then damage=(damage*berrymod).round if type == :FIRE
          when :PASSHOBERRY   then damage=(damage*berrymod).round if type == :WATER
          when :RINDOBERRY   then damage=(damage*berrymod).round if type == :GRASS
          when :WACANBERRY   then damage=(damage*berrymod).round if type == :ELECTRIC
          when :PAYAPABERRY   then damage=(damage*berrymod).round if type == :PSYCHIC
          when :YACHEBERRY   then damage=(damage*berrymod).round if type == :ICE
          when :HABANBERRY   then damage=(damage*berrymod).round if type == :DRAGON
          when :COLBURBERRY   then damage=(damage*berrymod).round if type == :DARK
          when :ROSELIBERRY   then damage=(damage*berrymod).round if type == :FAIRY
        end
      end
    end
    # pbModifyDamage - TODO
    if opponent.effects[:Minimize] && (move.move == :BODYSLAM || move.function==0x10 ||
      move.function==0x9B || move.function==0x137 || move.function == 0x806)
      damage=(damage*2.0).round
    end
    # "AI-specific calculations below"
    # Increased critical hit rates
    if @mondata.skill>=MEDIUMSKILL
      critrate = move.pbCritRate?(attacker,opponent)
      if critrate==2
        damage=(damage*1.25).round
      elsif critrate>2
        damage=(damage*1.5).round
      end
    end
    #Substitute damage
    if opponent.effects[:Substitute] > 0 && attacker.ability != :INFILTRATOR && !move.isSoundBased? &&
      move.move!=:SPECTRALTHIEF && move.move!=:HYPERSPACEHOLE && move.move!=:HYPERSPACEFURY && damage > opponent.hp/2
      damage=(opponent.hp/2.0).round
    end
    # Make sure damage is at least 1
    damage=1 if damage<1
    return damage
  end

  def pbBetterBaseDamage(move=@move,attacker=@attacker,opponent=@opponent)
    # Covers all function codes which have their own def pbBaseDamage
    aimem = getAIMemory(opponent)
    basedamage = move.basedamage
    basedamage = [attacker.happiness,250].min if attacker.crested == :LUVDISC
    case move.function
      when 0x12 # Fake Out
        return basedamage if attacker.turncount<=1
        return 0
      when 0x6A # SonicBoom
        return 140 if @battle.FE == :RAINBOW
        return 20
      when 0x6B # Dragon Rage
        return 140 if @battle.FE == :DIMENSIONAL || @battle.FE == :FROZENDIMENSION
        return 40
      when 0x6C # Super Fang, Nature's Madness, # Gen 9 Mod - Ruination
        if (move.move == :NATURESMADNESS) && (@battle.FE == :GRASSY || @battle.FE == :FOREST || @battle.FE == :NEWWORLD)
          return (opponent.hp*0.75).floor
        elsif (move.move == :NATURESMADNESS) && @battle.FE == :HOLY
          return (opponent.hp*0.66).floor
        end
        return (opponent.hp/2.0).floor
      when 0x6D # Night Shade
        return attacker.level*1.5 if (@battle.FE == :HAUNTED &&  move.move == :NIGHTSHADE || @battle.FE == :DEEPEARTH &&  move.move == :SEISMICTOSS)
        return attacker.level
      when 0x6E # Endeavor
        return 0 if pbAIfaster?() && attacker.hp >= opponent.hp
        return opponent.hp-attacker.hp if pbAIfaster?()
        if !aimem.any? {|moveloop| moveloop!=nil && [:ENDEAVOR,:METALBURST,:COUNTER,:MIRRORCOAT,:BIDE].include?(moveloop.move)}
          return opponent.hp - [attacker.hp-checkAIdamage(attacker,opponent,aimem), 1].max
        end
        return 20
      when 0x6F # Psywave
        return ((attacker.level + attacker.level*1.5)/2).floor
        return attacker.level
      when 0x70 # OHKO
        return 0 if move.move == :FISSURE && @battle.FE == :NEWWORLD
        return opponent.totalhp
      when 0x71 # Counter
        maxdam=60
        for j in aimem
          next if j.pbIsSpecial?() || j.basedamage<=1 || [:ENDEAVOR,:METALBURST,:COUNTER,:MIRRORCOAT,:BIDE].include?(j.move)
          tempdam = pbRoughDamage(j,opponent,attacker)*2
          maxdam=tempdam if tempdam>maxdam
        end
        return maxdam
      when 0x72 # Mirror Coat
        maxdam=60
        for j in aimem
          next if j.pbIsPhysical?() || j.basedamage<=1 || [:ENDEAVOR,:METALBURST,:COUNTER,:MIRRORCOAT,:BIDE].include?(j.move)
          tempdam = pbRoughDamage(j,opponent,attacker)*2
          maxdam=tempdam if tempdam>maxdam
        end
        return maxdam
      when 0x73 # Metal Burst
        return (1.5 * checkAIdamage(attacker,opponent,aimem)).floor unless aimem.any? {|moveloop| moveloop!=nil && [:ENDEAVOR,:METALBURST,:COUNTER,:MIRRORCOAT,:BIDE].include?(moveloop.move)}
      when 0x75, 0x12D # Surf, Shadow Storm
        return basedamage*2 if !$cache.moves[opponent.effects[:TwoTurnAttack]].nil? &&
        $cache.moves[opponent.effects[:TwoTurnAttack]].function == 0xCB # Dive
      when 0x76 # Earthquake
        return basedamage*2 if !$cache.moves[opponent.effects[:TwoTurnAttack]].nil? &&
        $cache.moves[opponent.effects[:TwoTurnAttack]].function == 0xCA # Dig
      when 0x77, 0x78 # Gust, Twister
        return basedamage*2 if !$cache.moves[opponent.effects[:TwoTurnAttack]].nil? &&
        ($cache.moves[opponent.effects[:TwoTurnAttack]].function == 0xC9 ||# Fly
        $cache.moves[opponent.effects[:TwoTurnAttack]].function == 0xCC ||# Bounce
        $cache.moves[opponent.effects[:TwoTurnAttack]].function == 0xCE )# Sky Drop
      when 0x79 # Fusion Bolt
        return basedamage*2 if @battle.previousMove == :FUSIONFLARE
      when 0x7A # Fusion Flare
        return basedamage*2 if @battle.previousMove == :FUSIONBOLT
      when 0x7B # Venoshock
        if opponent.status== :POISON
          return basedamage*2
        elsif @mondata.skill>=BESTSKILL
          if @battle.FE == :CORROSIVE || @battle.FE == :CORROSIVEMIST || @battle.FE == :WASTELAND || @battle.FE == :MURKWATERSURFACE # Corrosive/Corromist/Wasteland/Murkwater
            return basedamage*2
          end
        end
      when 0x7C # SmellingSalt
        return basedamage*2 if opponent.status== :PARALYSIS  && opponent.effects[:Substitute]<=0
      when 0x7D # Wake-Up Slap
        return basedamage*2 if opponent.status== :SLEEP && opponent.effects[:Substitute]<=0
      when 0x7E # Facade
        return basedamage*2 if attacker.status== :POISON || attacker.status== :BURN || attacker.status== :PARALYSIS
      when 0x7F # Hex
        if !opponent.status.nil?
          return basedamage*2
        elsif @mondata.skill>=BESTSKILL
          if @battle.FE == :INFERNAL
            return basedamage*2
          end
        end
      when 0x80 # Brine
        return basedamage*2 if opponent.hp<=(opponent.totalhp/2.0).floor
      when 0x85 # Retaliate
        return basedamage*2 if attacker.pbOwnSide.effects[:Retaliate]
      when 0x86 # Acrobatics
        return basedamage*2 if attacker.item.nil? || attacker.hasWorkingItem(:FLYINGGEM) || @battle.FE == :BIGTOP
      when 0x87 # Weather Ball
        return basedamage*2 if (@battle.pbWeather!=0 || @battle.FE == :RAINBOW)
      when 0x89 # Return
        return [attacker.happiness,250].min if attacker.crested == :LUVDISC
        return 102 if @battle.FE == :CONCERT4
        return [(attacker.happiness*2/5).floor,1].max
      when 0x8A # Frustration
        return 102 if @battle.FE == :CONCERT4
        return [((255-attacker.happiness)*2/5).floor,1].max
      when 0x8B # Eruption / Water Spout
        return [attacker.happiness,250].min if attacker.crested == :LUVDISC
        return 150 if @battle.FE == :CONCERT4
        return [(150*(attacker.hp.to_f)/attacker.totalhp).floor,1].max
      when 0x8C # Crush Grip / Wring Out / # Gen 9 Mod - Hard Press
        return [attacker.happiness,250].min if attacker.crested == :LUVDISC
        return [(100*(opponent.hp.to_f)/opponent.totalhp).floor,1].max if move.move == :HARDPRESS
        return 120 if (@battle.FE == :CONCERT4 || @battle.FE == :DEEPEARTH)
        return [(120*(opponent.hp.to_f)/opponent.totalhp).floor,1].max
      when 0x8D # Gyro Ball
        return [attacker.happiness,250].min if attacker.crested == :LUVDISC
        return 150 if (@battle.FE == :CONCERT4 || @battle.FE == :DEEPEARTH)
        ospeed=pbRoughStat(opponent,PBStats::SPEED)
        aspeed=pbRoughStat(attacker,PBStats::SPEED)
        return [[(25*ospeed/aspeed).floor,150].min,1].max
      when 0x8E # Stored Power
        mult=0
        for i in [PBStats::ATTACK,PBStats::DEFENSE,PBStats::SPEED,
            PBStats::SPATK,PBStats::SPDEF,PBStats::ACCURACY,PBStats::EVASION]
        mult+=attacker.stages[i] if attacker.stages[i]>0
        end
        bp = 20
        bp = 40 if move.move ==:POWERTRIP && @battle.FE == :FROZENDIMENSION
        return ([attacker.happiness,250].min)+(bp*mult) if attacker.crested == :LUVDISC
        return bp*(mult+1)
      when 0x8F # Punishment
        mult=0
        for i in [PBStats::ATTACK,PBStats::DEFENSE,PBStats::SPEED,
            PBStats::SPATK,PBStats::SPDEF,PBStats::ACCURACY,PBStats::EVASION]
        mult+=opponent.stages[i] if opponent.stages[i]>0
        end
        return [([attacker.happiness,250].min)+(20*mult),500].min if attacker.crested == :LUVDISC
        return [20*(mult+3),200].min
      when 0x91 # Fury Cutter
        return basedamage * 2**(attacker.effects[:FuryCutter])
      when 0x92 # Echoed Voice
        return basedamage*(attacker.effects[:EchoedVoice]+1)
      when 0x94 # Present
        return [attacker.happiness,250].min if attacker.crested == :LUVDISC
        return 50
      when 0x95 # Magnitude
        damage = 71
        damage = 10 if @battle.FE == :CONCERT1
        damage = 150 if @battle.FE == :CONCERT4
        damage = [attacker.happiness,250].min if attacker.crested == :LUVDISC
        damage *= 2 if !$cache.moves[opponent.effects[:TwoTurnAttack]].nil? && $cache.moves[opponent.effects[:TwoTurnAttack]].function==0xCA # Dig
        return damage
      when 0x96 # Natural Gift
        return [attacker.happiness,250].min if attacker.crested == :LUVDISC
        return 100 if @battle.FE == :CONCERT4
        return !PBStuff::NATURALGIFTDAMAGE[attacker.item].nil? ? PBStuff::NATURALGIFTDAMAGE[attacker.item] : 1
      when 0x97 # Trump Card
        return [attacker.happiness,250].min if attacker.crested == :LUVDISC
        return 200 if @battle.FE == :CONCERT4
        dmgs=[200,80,60,50,40]
        ppleft=[move.pp-1,4].min   # PP is reduced before the move is used
        return dmgs[ppleft]
      when 0x98 # Flail / Reversal
        return [attacker.happiness,250].min if attacker.crested == :LUVDISC
        return 200 if @battle.FE == :CONCERT4
        n=(48*(attacker.hp.to_f)/attacker.totalhp).floor
        return 200 if n<2
        return 150 if n<5
        return 100 if n<10
        return 80 if n<17
        return 40 if n<33
        return 20
      when 0x99 # Electro Ball
        return [attacker.happiness,250].min if attacker.crested == :LUVDISC
        return 150 if @battle.FE == :CONCERT4
        n=(attacker.pbSpeed/opponent.pbSpeed).floor
        return 150 if n>=4
        return 120 if n>=3
        return 80 if n>=2
        return 60 if n>=1
        return 40
      when 0x9A # Low Kick / Grass Knot
        return [attacker.happiness,250].min if attacker.crested == :LUVDISC
        return 120 if (@battle.FE == :CONCERT4 || @battle.FE == :DEEPEARTH)
        weight=opponent.weight
        return 120 if weight>2000
        return 100 if weight>1000
        return 80 if weight>500
        return 60 if weight>250
        return 40 if weight>100
        return 20
      when 0x9B # Heavy Slam / Heat Crash
        return [attacker.happiness,250].min if attacker.crested == :LUVDISC
        return 120 if (@battle.FE == :CONCERT4 || @battle.FE == :DEEPEARTH)
        n=(attacker.weight/opponent.weight).floor
        return 120 if n>=5
        return 100 if n>=4
        return 80 if n>=3
        return 60 if n>=2
        return 40
      when 0xA0, 0x90B # Frost Breath, Flower Trick
        return basedamage*1.5
      when 0xBD, 0xBE, 0x91F # Double Kick, Twineedle, Tachyon Cutter
        return basedamage*2
      when 0xBF # Triple Kick, Triple Axel, Thunder Raid
        return basedamage*6
      when 0xC0 # Bullet Seed, Pin Missile, Arm Thrust, Bone Rush, Icicle Spear, Tail Slap, Spike Cannon, Comet Punch, Furey Swipes, Barrage, Double Slap, Fury Attack, Rock Blast, Water Shuriken
        if attacker.ability == :SKILLLINK || attacker.ability == :TECHLINK
          return basedamage*5
        elsif attacker.item == :LOADEDDICE
          return (basedamage*9/2).floor
        else
          return (basedamage*19/6).floor
        end
      when 0xC1 # Beat Up
        party=@battle.pbPartySingleOwner(attacker.index)
        party=party.filter {|mon| !mon.nil? && !mon.isEgg? && mon.hp>0 && mon.status.nil?}
        basedamage=0
        party.each {|mon| basedamage+= 5+(mon.baseStats[1]/10)}
        return basedamage
      when 0xC4 # SolarBeam
        return (basedamage*0.5).floor if @battle.pbWeather!=0 && @battle.pbWeather!=:SUNNYDAY
      when 0xD0 # Whirlpool
        if @mondata.skill>=MEDIUMSKILL
          return basedamage*2 if !$cache.moves[opponent.effects[:TwoTurnAttack]].nil? &&
          $cache.moves[opponent.effects[:TwoTurnAttack]].function==0xCB # Dive
        end
      when 0xD3 # Rollout
        if @mondata.skill>=MEDIUMSKILL
          return basedamage*2 if attacker.effects[:DefenseCurl]
        end
      when 0xD4 # Bide
        return checkAIdamage(attacker,opponent,aimem) unless aimem.any? {|moveloop| moveloop!=nil && [:ENDEAVOR,:METALBURST,:COUNTER,:MIRRORCOAT,:BIDE].include?(moveloop.move)}
      when 0xE1 # Final Gambit
        return attacker.hp
      when 0xF0 # Knock Off
        return basedamage*1.5 if opponent.item && !@battle.pbIsUnlosableItem(opponent,opponent.item)
      when 0xF1 # Covet / Thief
        return basedamage*2 if @battle.FE == :BACKALLEY && opponent.item && !@battle.pbIsUnlosableItem(opponent,opponent.item)
      when 0xF7 # Fling
        if attacker.item.nil?
          return 0
        else
          return [attacker.happiness,250].min if attacker.crested == :LUVDISC
          return 130 if @battle.FE == :CONCERT4
          return 10 if !attacker.item.nil? && pbIsBerry?(attacker.item)
          return PBStuff::FLINGDAMAGE[attacker.item] if PBStuff::FLINGDAMAGE[attacker.item]
          return 1
        end
      when 0x113 # Spit Up
        return [attacker.happiness,250].min if attacker.crested == :LUVDISC
        return 300 if @battle.FE == :CONCERT4
        return 100*attacker.effects[:Stockpile]
      when 0x118 # Gravity
        return (opponent.hp/2.0).floor if @battle.FE == :DEEPEARTH
      when 0x142 # Topsy Turvy
        if @battle.FE == :DEEPEARTH
          return [attacker.happiness,250].min if attacker.crested == :LUVDISC
          weight=opponent.weight*2
          return 120 if weight>2000
          return 100 if weight>1000
          return 80 if weight>500
          return 60 if weight>250
          return 40 if weight>100
          return 20
        end
      when 0x161 # First Impression
        return basedamage if attacker.turncount<=1
        return 0
      when 0x171 # Stomping Tantrum
        return basedamage*2 if attacker.effects[:Tantrum]
      when 0x178 # Dynamax Cannon, Behemoth Blade, Behemoth Bash
        return basedamage*2 if opponent.isMega? || opponent.isUltra? || opponent.isPrimal?
      when 0x17E # Dragon Darts
        return basedamage*2 if !@battle.doublebattle || move.pbDragonDartTargetting(attacker).length < 2
      when 0x181 # Fishious Rend/Bolt beak
        return basedamage*2 if pbAIfaster?(move,nil,attacker,opponent)
      when 0x18B # Grav Apple
        return basedamage * 1.5 if @battle.state.effects[:Gravity] != 0
      when 0x307 # Scale Shot
        if attacker.ability == :SKILLLINK || attacker.ability == :TECHLINK
          return basedamage*5
        else
          return (basedamage*19/6).floor
        end
      when 0x30A # Misty explosion
        return basedamage * 1.5 if @battle.FE == :MISTY || @battle.state.effects[:MISTY] > 0
      when 0x311 # Rising Voltage, # Gen 9 Mod - Psyblade
        return basedamage*2 if (@battle.FE == :ELECTERRAIN || @battle.state.effects[:ELECTERRAIN] > 0) && !opponent.isAirborne? && @move.move == :RISINGVOLTAGE
        return basedamage*1.5 if (@battle.FE == :ELECTERRAIN || @battle.state.effects[:ELECTERRAIN] > 0) && !opponent.isAirborne? && @move.move == :PSYBLADE
      when 0x314 # Lash Out
        # I GENUINELY do not know when this moves condition is ever gonna be fulfilled while the AI choses a move but just in case - Fal
        return basedamage*2 if attacker.effects[:LashOut]
      when 0x319 # Surging Strikes
        return basedamage*4.5
      when 0x321 # Expanding Force
        return basedamage*1.5 if (@battle.FE == :PSYTERRAIN || @battle.state.effects[:PSYTERRAIN] > 0) && !attacker.isAirborne?
      when 0x502 # Barb Barrage
        if opponent.status== :POISON
          return basedamage*2
        elsif @mondata.skill>=BESTSKILL
          if @battle.FE == :CORROSIVE || @battle.FE == :CORROSIVEMIST || @battle.FE == :WASTELAND || @battle.FE == :MURKWATERSURFACE # Corrosive/Corromist/Wasteland/Murkwater
            return basedamage*2
          end
        end
      when 0x504 # Infernal Parade
        if !opponent.status.nil?
          return basedamage*2
        elsif @mondata.skill>=BESTSKILL
          if @battle.FE == :HAUNTED
            return basedamage*2
          end
        end
      # Rejuv Customs
      when 0x202 # Fever Pitch
        return [attacker.happiness,250].min if attacker.crested == :LUVDISC
        return 40 if @battle.FE == :CONCERT1
        return 130 if @battle.FE == :CONCERT4
        return 74
      when 0x209 # Bunraku Beatdown
        return basedamage+(30*opponent.pbFaintedPokemonCount) if attacker.ability == :WORLDOFNIGHTMARES
        return [basedamage+(15*attacker.pbFaintedPokemonCount),165].min
      when 0x20C # Gilded Helix
        return basedamage*2 if move.move == :GILDEDHELIX
      # Gen 9 Mod - Gen 9 Moves Below
      when 0x904 # Collision Course / Electro Drift
        return basedamage*1.33 if pbTypeModNoMessages(@move.pbType(@attacker))>4
      when 0x910 # Last Respects
        faintedCounter=@battle.pbPartySingleOwner(attacker.index).find_all {|mon| mon && !mon.isEgg? && mon.hp<=0}
        return basedamage + (50*faintedCounter.length)
      when 0x909 # Fickle Beam
        return basedamage*1.3 # Takes into account 30% chance to double in base power.
                              # Is it smarter for the AI to do this or to always assume 80 base power?
                              # Who knows for sure, this seems to work well enough though so I'm leaving it like this.
      when 0x914 # Population Bomb
        if attacker.ability == :SKILLLINK || attacker.ability == :TECHLINK     # Assumes we hit the single 90% accuracy check to not make maths egregious
          return (basedamage*10)
        elsif attacker.item == :LOADEDDICE
          return (basedamage*7).floor         # Assumes we hit the single 90% accuracy check to not make maths egregious
        else
          return (basedamage*586/100).floor   # Average number of hits with no modifiers ~= 5.86
        end
      when 0x915 # Rage Fist
        rageFistCounter=@battle.getBattlerHit(attacker)
        return basedamage+(50*rageFistCounter)
      # Z-moves
      when 0x809 # Guardian of Alola
        return (opponent.hp*0.99).floor if @battle.FE == :FOREST
        return (opponent.hp*0.75).floor
    end
    return basedamage
  end

  def pbStatusDamage(move)
    return PBStuff::STATUSDAMAGE[move.move] if PBStuff::STATUSDAMAGE[move.move]
    return 0
  end

  def pbRoughDamageAfterBoosts(move=@move,attacker=@attacker,opponent=@opponent,oppboosts: {},attboosts:{})
    # Set the Default value of the hashes, not really necessary
    oppboosts.default = 0
    attboosts.default = 0

    # Clone the stages arrays
    oppstages = opponent.stages.clone
    attstages = attacker.stages.clone

    # Apply stat changes to pokemons
    for stat in oppboosts.keys
      opponent.stages[stat] += oppboosts[stat]
      opponent.stages[stat].clamp(-6,6)
    end
    for stat in attboosts.keys
      attacker.stages[stat] += attboosts[stat]
      attacker.stages[stat].clamp(-6,6)
    end

    # Recalculate the damge
    damage = pbRoughDamage(move,attacker,opponent)

    # Revert the stat changes
    opponent.stages = oppstages
    attacker.stages = attstages

    return damage
  end


  def mirrorShatter
      return true
  end

  def caveCollapse
    return false
  end

  def mirrorNeverMiss
    return (@attacker.stages[PBStats::ACCURACY] < 0 || @opponent.stages[PBStats::EVASION] > 0 || @opponent.item == :BRIGHTPOWDER ||
      @opponent.item == :LAXINCENSE || accuracyWeatherAbilityActive?(@opponent) || @opponent.vanished) &&
       @opponent.ability != :NOGUARD && @attacker.ability != :NOGUARD && !(@attacker.ability == :FAIRYAURA && @battle.FE == :FAIRYTALE)
  end

  def mistExplosion
    return !@battle.pbCheckGlobalAbility(:DAMP)
  end

  def ignitecheck
    return @battle.state.effects[:WaterSport] <= 0 && @battle.pbWeather != :RAINDANCE
  end

  def suncheck
  end

  def pbAegislashStats(aegi)
    if aegi.form==1
        return aegi
    else
      bladecheck = aegi.clone
      bladecheck.stages = aegi.stages.map(&:clone)
      bladecheck.form = 1
      bladecheck.stages[PBStats::ATTACK] += 1 if @battle.FE == :FAIRYTALE && bladecheck.stages[PBStats::ATTACK]<6
      return bladecheck
    end
  end

  def moveSuccesful?(move, attacker, opponent)
    if move.pbIsPriorityMoveAI(attacker)
      return false if (@battle.FE == :PSYTERRAIN || @battle.state.effects[:PSYTERRAIN] > 0) && !opponent.isAirborne?
      # Gen 9 Mod - Armor Tail
      return false if opponent.ability == :DAZZLING || opponent.ability == :ARMORTAIL || opponent.ability == :QUICKREFLEX ||opponent.ability == :QUEENLYMAJESTY || (opponent.ability == :MIRRORARMOR && @battle.FE == :STARLIGHT)
      # Gen 9 Mod - Armor Tail
      return false if opponent.pbPartner.ability == :DAZZLING || opponent.pbPartner.ability == :ARMORTAIL || opponent.pbPartner.ability == :QUICKREFLEX || opponent.pbPartner.ability == :QUEENLYMAJESTY || (opponent.pbPartner.ability == :MIRRORARMOR && @battle.FE == :STARLIGHT)
      return false if @battle.FE != :BEWITCHED && attacker.ability == :PRANKSTER && opponent.hasType?(:DARK) && move.pbIsStatus?
    end
    return true
  end

#####################################################
## Utility functions                  #
#####################################################

  def moldBreakerCheck(battler)
    return (battler.ability==:MOLDBREAKER || battler.ability==:TERAVOLT || battler.ability==:TURBOBLAZE) && @opponent.item != :ABILITYSHIELD # Gen 9 Mod - Added Ability Shield Check
  end

  def myceliumMightCheck(battler, move = @move)
    return battler.ability==:MYCELIUMMIGHT && move.category == :status && @opponent.item != :ABILITYSHIELD # Gen 9 Mod - Added Mycelium Might & Ability Shield Check
  end

  def unseenFistCheck(battler, move = @move)
    return battler.ability == :UNSEENFIST && !(battler.item == :PUNCHINGGLOVE && move.punchMove?) # Gen 9 Mod - Unsee Fist needs to check Punching Glove
  end

  def hydrationCheck(battler)
    return true if battler.ability == :HYDRATION && (@battle.pbWeather== :RAINDANCE || @battle.FE == :WATERSURFACE || @battle.FE == :UNDERWATER)
    return true if battler.ability == :NATURALCURE && @battle.FE == :BEWITCHED # may no be hydration but it acts the same
  end

  def notOHKO?(attacker,opponent, immediate = false)
    return false if @battle.pbWeather == :HAIL && !(attacker.hasType?(:ICE) || [:ICEBODY,:SNOWCLOAK,:SLUSHRUSH,:LUNARIDOL,:MAGICGUARD,:OVERCOAT,:TEMPEST].include?(attacker.ability) || (HAILSNOWMOD == "Snow" || KAIZOMOD)) && !immediate
    return false if @battle.pbWeather == :SANDSTORM && !(attacker.hasType?(:ROCK) || attacker.hasType?(:GROUND) || attacker.hasType?(:STEEL) || [:SANDFORCE,:SANDRUSH,:SANDVEIL,:MAGICGUARD,:OVERCOAT,:TEMPEST].include?(attacker.ability)) && !immediate
    return false if @battle.pbWeather == :SHADOWSKY && !(attacker.hasType?(:SHADOW) || [:MAGICGUARD,:OVERCOAT,:TEMPEST].include?(attacker.ability)) && !immediate
    return false if attacker.hp != attacker.totalhp
    return false if attacker.ability == :PARENTALBOND || attacker.ability == :SKILLLINK || attacker.ability == :TECHLINK || attacker.crested == :TYPHLOSION
    bestmove, damage = checkAIMovePlusDamage(opponent, attacker)
    return false if bestmove.pbIsMultiHit && damage >= attacker.hp && !(attacker.ability == :RESUSCITATION && attacker.form == 1)
    return true  if attacker.ability == :RESUSCITATION && attacker.form == 1
    return true  if attacker.hasWorkingItem(:FOCUSSASH)
    return true  if @battle.FE == :CHESS && attacker.pokemon.piece==:PAWN && !attacker.damagestate.pawnsturdyused && @mondata.skill >= HIGHSKILL
    return true   if attacker.ability == :STURDY && !moldBreakerCheck(opponent)
    return true  if Rejuv && attacker.crested == :RAMPARDOS && attacker.pokemon.rampCrestUsed == false
    return true  if @battle.FE == :COLOSSEUM && attacker.ability == :STALWART && !moldBreakerCheck(opponent)
    return false
  end

  def canGroundMoveHit?(battler)
    return true if battler.item == :IRONBALL if @battle.FE != :DEEPEARTH
    return true if battler.effects[:Ingrain]
    return true if battler.effects[:SmackDown]
    return false if [:MAGNETPULL,:CONTRARY,:UNAWARE,:OBLIVIOUS].include?(battler.ability) && @battle.FE == :DEEPEARTH
    return true if @battle.state.effects[:Gravity]!=0
    return true if @battle.FE == :CAVE
    return false if battler.hasType?(:FLYING) && battler.effects[:Roost]==false && @battle.FE != :INVERSE
    return false if [:LEVITATE,:SOLARDIOL,:LUNARIDOL].include?(battler.ability)
    return false if battler.item == :AIRBALLOON && battler.itemWorks? && !battler.effects[:DesertsMark]
    return false if battler.effects[:MagnetRise]!=0
    return false if battler.effects[:Telekinesis]>0
    return true
    end

  def secondaryEffectNegated?(move = @move, attacker = @attacker, opponent = @opponent)
    return move.basedamage > 0 && (((opponent.ability == :SHIELDDUST || opponent.hasWorkingItem(:COVERTCLOAK)) && !([0x1C,0x1D,0x1E,0x1F,0x20,0x2D,0x2F,0x147,0x186,0x307,0x103,0x105,0x204,0x900].include?(move.function))) || attacker.ability == :SHEERFORCE) # Gen 9 Mod - Added Covert Cloak and exception for Ceaseless Edge and Stone Axe functions
  end

  def seedProtection?(battler = @attacker)
    return battler.effects[:KingsShield] || battler.effects[:BanefulBunker] || battler.effects[:SpikyShield] || battler.effects[:SilkTrap] || battler.effects[:BurningBulwark] # Gen 9 Mod - Added Silk Trap and Burning Bulwark
  end

  def accuracyWeatherAbilityActive?(battler)
    return (battler.ability == :SANDVEIL && (@battle.pbWeather== :SANDSTORM || @mondata.skill >=BESTSKILL && (@battle.FE == :DESERT || @battle.FE == :ASHENBEACH))) ||
    (battler.ability == :SNOWCLOAK && (@battle.pbWeather== :HAIL || @mondata.skill >=BESTSKILL && (@battle.FE == :ICY || @battle.FE == :SNOWYMOUNTAIN)))
  end

  def firstOpponent
    return  @battle.doublebattle ? (@attacker.pbOppositeOpposing.hp > 0 ? @attacker.pbOppositeOpposing : @attacker.pbCrossOpposing) : @attacker.pbOppositeOpposing
  end

end

#####################################################
## Other Classes
#####################################################

class PokeBattle_Move_FFF < PokeBattle_Move # Fake move used by AI to determine damage if no damaging AI memory move
  def initialize(battle, user, type)
    type = :QMARKS if !type
    @move = :FAKEMOVE
    @battle = battle
    hash = {
      :name => "Fake Move",
      :function => 0xFFF,
      :basedamage => (user.level >= 40 ? 80 : [2 * user.level, 40].max),
      :type => type,
      :effect => 0,
      :moreeffect => 0,
      :category => (user.attack > user.spatk ? 0 : 1),
      :accuracy => 100,
      :target => :SingleNonUser,
      :maxpp => 15,
      :recoil => 0,
    }
    @priority    = 0
    @zmove       = false
    @user        = user
    @data = MoveData.new(@move, hash)
    # these attributes do need to be assigned but we also need the data seperately for reasons (idk do we?)
    if @data
      @function = @data.function
      @type       = @data.type
      @category   = @data.category
      @basedamage = @data.basedamage
      @accuracy   = @data.accuracy
      @maxpp      = @data.maxpp
      @target     = @data.target
      @effect     = @data.checkFlag?(:effect, 0)
      @moreeffect = @data.checkFlag?(:moreeffect, 0)
      @recoil     = @data.checkFlag?(:recoil, 0)
    end
  end
end

class PokeBattle_AI_Info #info per battler for debuglogging
  attr_accessor :battler_name
  attr_accessor :battler_item
  attr_accessor :battler_ability
  attr_accessor :field_effect
  attr_accessor :items
  attr_accessor :items_scores
  attr_accessor :switch_scores
  attr_accessor :switch_name
  attr_accessor :should_switch_score
  attr_accessor :move_names
  attr_accessor :init_score_moves
  attr_accessor :final_score_moves
  attr_accessor :chosen_action
  attr_accessor :opponent_name
  attr_accessor :expected_damage
  attr_accessor :expected_damage_name
  attr_accessor :battler_hp_percentage

  def initialize
    @battler_name                = ""
    @battler_item                = ""
    @battler_ability              = ""
    @battler_hp_percentage            = 0
    @field_effect                = 0
    @items                     = []
    @items_scores                 = []
    @switch_scores                 = []
    @switch_name                 = []
    @should_switch_score            = 0
    @move_names                  = []
    @opponent_name                = []
    @init_score_moves              = []
    @final_score_moves              = []
    @chosen_action                = ""
    @expected_damage              = []
    @expected_damage_name            = []
  end

  def reset(battler)
    @battler_name                = battler.nil? ? "" : battler.name
    @battler_item                = battler.nil? || battler.item.nil? ? "" : getItemName(battler.item)
    @battler_ability              = battler.nil? || battler.ability.nil? ? "" : getAbilityName(battler.ability)
    @battler_hp_percentage            = (battler.hp*100.0 / battler.totalhp).round(1)
    @field_effect                = battler.battle.FE
    @items                     = []
    @items_scores                 = []
    @switch_scores                 = []
    @switch_name                 = []
    @should_switch_score            = 0
    @move_names                 = []
    @opponent_name                = []
    @init_score_moves              = []
    @final_score_moves              = []
    @chosen_action                = ""
    @expected_damage              = []
    @expected_damage_name            = []
  end

  def logAIScorings()
    return if !$INTERNAL
    to_be_printed = "\n ______________________________________________________________________________ \n"
    to_be_printed += "Scoring for battler: " + @battler_name + " , HP percentage: #{@battler_hp_percentage} %\n"
    to_be_printed += "Held Item: " + @battler_item + " , Ability: " + @battler_ability + " , Field: " + PokeBattle_Field.getFieldName(@field_effect).to_s + "\n"
    to_be_printed += " "*60 +  +"|AI Scores\n"

    #Add scores for current hp and the expected damage it will take
    @expected_damage.each_with_index {|_,i|
    to_be_printed += "Expected Damage taken from #{@expected_damage_name[i]}".ljust(60) + "|#{@expected_damage[i]} % \n"
    }
    to_be_printed += "\n"

    #Add scores for items and switching to string
    to_be_printed += "Scoring for Switching to other mon".ljust(60) + "|"  + "#{@should_switch_score} \n \n"
    to_be_printed += "Scoring for items".ljust(60) + "|".ljust(21) + "| \n"  if @items.length != 0
    @items.each_with_index {|item_name, index|
    to_be_printed += item_name.ljust(60) + "|" + @items_scores[index].to_s.ljust(20) + "\n"
    }

    # Sort the move order so moves are grouped together
    @opponent_name.sort_by!.with_index{|_,i|@move_names[i]}
    @init_score_moves.sort_by!.with_index{|_,i|@move_names[i]}
    @final_score_moves.sort_by!.with_index{|_,i|@move_names[i]}
    @move_names.sort!

    # Now add these badboys to the string
    @move_names.each_with_index {|movename,index|
    to_be_printed += "#{movename} vs #{@opponent_name[index]}, Init scoring move: ".ljust(60) + "|#{@init_score_moves[index]} \n"
    to_be_printed += "#{movename} vs #{@opponent_name[index]}, Final scoring move: ".ljust(60) +"|#{@final_score_moves[index]} \n"
    to_be_printed += "\n"
    }
    to_be_printed += "Final action chosen:".ljust(60) + "|#{@chosen_action}".ljust(20)
    to_be_printed += "\n ______________________________________________________________________________ \n"

    #put to console
    $stdout.print(to_be_printed)
    PBDebug.log(to_be_printed)
  end

  def logAISwitching()
    return if !$DEBUG
    to_be_printed = "Scoring for switching from: " + @battler_name + "\n"
    to_be_printed += " "*60 +"|New AI\n"
    @switch_name.each_with_index {|name, index|
      to_be_printed += "Score for switching to #{name}".ljust(60) + "|#{@switch_scores[index]} \n"
    }
    to_be_printed += "Switch chosen = ".ljust(60) + "|#{@switch_name[@switch_scores.index(@switch_scores.max)]} \n"
    to_be_printed += "\n ______________________________________________________________________________ \n"
    $stdout.print(to_be_printed)
    PBDebug.log(to_be_printed)
  end
end
