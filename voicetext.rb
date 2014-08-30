# -*- coding: utf-8 -*-

require "open3"
require "workers"
require 'voicetext'

Plugin.create(:voicetext) do

    # 馬鹿にしか見えない行らしいですよ
    @voicetext = Voicetext.new('NDNjdzl3ZmEwNXR1cWVtZA==\n'.unpack('m')[0])

    # 読み上げ処理のキュー
    @pool = nil

    # config に設定項目を追加
    settings("VoiceText") do
        settings("基本設定") do
            input '音声再生コマンド', :voicetext_read_command
            input '作業ディレクトリ', :voicetext_working_directory
        end
        settings("読み上げ設定") do
            select '読み上げる人', :voicetext_speaker, 'show' => 'show', 'haruka' => 'haruka', 'hikari' => 'hikari', 'takeru' => 'takeru'
            select '感情', :voicetext_option_emotion, '' => '普通', :happiness => 'うれしんでる', :anger => 'おこってる', :sadness => 'かなしんでる'
            #select '感情レベル', :voicetext_option_emotion_level, 1 => '普通', 2 => '感情的'
            adjustment 'ピッチ倍率(%)', :voicetext_option_pitch, 50, 200
            adjustment 'しゃべる速さの倍率(%)', :voicetext_option_speed, 50, 400
            adjustment '音量倍率(%)', :voicetext_option_volume, 50, 400
        end
    end

    on_boot do |service|
        # 設定のデフォルト値設定
        UserConfig[:voicetext_read_command] ||= "aplay"
        UserConfig[:voicetext_working_directory] ||= "~/tmp"

        # VoiceText のオプション
        UserConfig[:voicetext_speaker] ||= 'haruka'
        UserConfig[:voicetext_option_emotion] ||= ''
        UserConfig[:voicetext_option_emotion_level] ||= 1
        UserConfig[:voicetext_option_pitch] ||= 100
        UserConfig[:voicetext_option_speed] ||= 100
        UserConfig[:voicetext_option_volume] ||= 100

        # 受信ツイート読み上げ機能初期化
        @pool = Workers::Pool.new(:size => 1)
    end

    # VoiceText に読みあげてもらうコマンド
    # 選択されているメッセージを順番に読みあげていく
    command(:voicetext, name: 'VoiceText', condition: Plugin::Command[:HasMessage], visible: true, role: :timeline) do |opt|
        @pool.perform do
            for message in opt.messages do
                Plugin.filtering(:voicetext_read, message.body)
            end
        end
    end

    # 渡された文字列を読み上げる
    # 必要であれば長文を分割して順次読み上げる。
    filter_voicetext_read do |text|

        @pool.perform do
            if text.length < 200 then
                readMessage text
            else
                # 200 文字を肥えていた場合、句点で分割する
                for splitted_text in text.split(/(。|\.)/) do
                    readMessage splitted_text
                end
            end
        end

        [text]
    end

    # 渡された文字列を読み上げる
    # 1. VoiceText へリクエストを投げる
    # 2. 結果の WAV を一時ファイルに保存
    # 3. 外部プログラムで音声再生
    def readMessage(text)
        speaker = UserConfig[:voicetext_speaker]

        option = {
            :emotion => UserConfig[:voicetext_option_emotion].to_s,
            #:emotion_level => UserConfig[:voicetext_option_emotion_level].to_s,
            :pitch => '=' + UserConfig[:voicetext_option_pitch].to_s,
            :speed => '=' + UserConfig[:voicetext_option_speed].to_s,
            :volueme => '=' + UserConfig[:voicetext_option_volume].to_s
        }

        # 1. VoiceText へリクエストを投げる
        voice = @voicetext.tts(text, speaker, option)

        # 2. 結果の WAV を一時ファイルに保存
        tmp_voice_file = create_tmp_file voice

        # 3. 外部プログラムで音声再生
        read = "#{UserConfig[:voicetext_read_command]} #{tmp_voice_file} 2> /dev/null"
        Open3.capture3("#{read}")

        # 一時ファイル削除
        File.delete(tmp_voice_file) if File.exist?(tmp_voice_file)
    end

    # 音声再生コマンドへ渡すための wav ファイルを作成し、
    # そのファイルパスを返却する。
    def create_tmp_file(voice)
        working_dir = UserConfig[:voicetext_working_directory]
        tmp_voice_file = "#{working_dir}/voicetext_#{Time.now.strftime('%Y%m%d%H%M%S')}.wav"
        tmp_voice_file = File.expand_path(tmp_voice_file)

        # 一時ファイル作成
        f = File.open(tmp_voice_file,'wb')
        f.write(voice)

        return tmp_voice_file
    end
end
