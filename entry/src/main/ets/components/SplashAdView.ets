const SPLASH_DURATION_MS: number = 3000;
const SPLASH_TICK_MS: number = 50;

@Component
export struct SplashAdView {
  @Link visible: boolean;
  @State countdown: number = 3;
  @State progress: number = 0;
  private splashTimer: number = -1;
  private splashStartMs: number = 0;

  aboutToAppear(): void {
    this.startCountdown();
  }

  aboutToDisappear(): void {
    this.clearTimer();
  }

  private clearTimer(): void {
    if (this.splashTimer >= 0) {
      clearInterval(this.splashTimer);
      this.splashTimer = -1;
    }
  }

  private dismiss(): void {
    this.clearTimer();
    this.visible = false;
  }

  private startCountdown(): void {
    this.clearTimer();
    this.countdown = 3;
    this.progress = 0;
    this.splashStartMs = Date.now();
    this.splashTimer = setInterval(() => {
      const elapsed = Date.now() - this.splashStartMs;
      this.progress = Math.min(100, (elapsed / SPLASH_DURATION_MS) * 100);
      const remain = Math.ceil((SPLASH_DURATION_MS - elapsed) / 1000);
      this.countdown = Math.max(0, remain);
      if (elapsed >= SPLASH_DURATION_MS) {
        this.dismiss();
      }
    }, SPLASH_TICK_MS);
  }

  @Builder
  energyStripe(top: number, left: number, width: number, rotate: number) {
    Row()
      .width(width)
      .height(3)
      .backgroundColor('#FFD52C88')
      .borderRadius(2)
      .rotate({ angle: rotate })
      .position({ x: left, y: top })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 145,
          colors: [['#071510', 0], ['#0F2E1F', 0.45], ['#1A4D32', 0.78], ['#0B1F14', 1]]
        })

      this.energyStripe(120, -20, 180, -18)
      this.energyStripe(280, 220, 140, 12)
      this.energyStripe(420, 40, 200, -8)

      Column()
        .width(220)
        .height(220)
        .borderRadius(110)
        .backgroundColor('#35A95B18')
        .position({ x: '55%', y: '18%' })

      Column()
        .width(160)
        .height(160)
        .borderRadius(80)
        .backgroundColor('#FFD52C12')
        .position({ x: '-8%', y: '52%' })

      Column() {
        Blank().layoutWeight(1)

        Column() {
          Text('⌁  MYDOMAI')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFD52C')
            .letterSpacing(2)
          Text('跑步圈地 · 竞技征服')
            .fontSize(11)
            .fontColor('#9FD4B0')
            .margin({ top: 6 })

          Text('脚步即锋刃')
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
            .margin({ top: 28 })
            .letterSpacing(1)
            .textShadow({ radius: 8, color: '#00000066', offsetX: 0, offsetY: 2 })

          Text('圈地以为王')
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFD52C')
            .margin({ top: 8 })
            .letterSpacing(1)
            .textShadow({ radius: 8, color: '#00000055', offsetX: 0, offsetY: 2 })

          Row() {
            Text('🏃').fontSize(22)
            Text('每一步都是进攻').fontSize(13).fontColor('#C8E6D0').margin({ left: 8 })
          }.margin({ top: 22 })

          Row() {
            Text('⚔').fontSize(22)
            Text('每一圈都是王座').fontSize(13).fontColor('#C8E6D0').margin({ left: 8 })
          }.margin({ top: 10 })

          Row() {
            Text('🗺').fontSize(20)
            Text('👑').fontSize(20).margin({ left: 12 })
            Text('⌁').fontSize(20).fontColor('#FFD52C').margin({ left: 12 })
          }.margin({ top: 24 })
        }
        .width('100%')
        .padding({ left: 28, right: 28 })
        .alignItems(HorizontalAlign.Start)

        Blank().layoutWeight(1)

        Column() {
          Row() {
            Text('即将进入战场')
              .fontSize(11)
              .fontColor('#8FBFA0')
            Blank().layoutWeight(1)
            Text(`${this.countdown}s`)
              .fontSize(11)
              .fontColor('#FFD52C')
              .fontWeight(FontWeight.Bold)
          }.width('100%')

          Stack({ alignContent: Alignment.Start }) {
            Row()
              .width('100%')
              .height(4)
              .backgroundColor('#FFFFFF18')
              .borderRadius(2)
            Row()
              .width(`${this.progress}%`)
              .height(4)
              .backgroundColor('#FFD52C')
              .borderRadius(2)
          }
          .width('100%')
          .height(4)
          .margin({ top: 8 })
        }
        .width('100%')
        .padding({ left: 28, right: 28, bottom: 36 })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .backgroundColor('#071510')
    .hitTestBehavior(HitTestMode.Block)
    .zIndex(999)
  }
}
