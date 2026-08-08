/** 闭环内广告预设（知名品牌风格化 Logo，非官方商标素材） */
export interface LoopAdPreset {
  id: string;
  brand: string;
  emoji: string;
  bgColor: string;
  fgColor: string;
  slogan: string;
}

export class LoopAdCatalog {
  static readonly NONE_ID: string = '';

  static getPresets(): Array<LoopAdPreset> {
    const nike: LoopAdPreset = {
      id: 'nike',
      brand: 'Nike',
      emoji: '✔️',
      bgColor: '#111111',
      fgColor: '#FFFFFF',
      slogan: 'Just Do It'
    };
    const adidas: LoopAdPreset = {
      id: 'adidas',
      brand: 'adidas',
      emoji: '🔺',
      bgColor: '#000000',
      fgColor: '#FFFFFF',
      slogan: 'Impossible is Nothing'
    };
    const starbucks: LoopAdPreset = {
      id: 'starbucks',
      brand: 'Starbucks',
      emoji: '☕',
      bgColor: '#00704A',
      fgColor: '#FFFFFF',
      slogan: 'Coffee and Cheer'
    };
    const mcdonalds: LoopAdPreset = {
      id: 'mcdonalds',
      brand: 'McDonalds',
      emoji: '🍟',
      bgColor: '#FFC72C',
      fgColor: '#DA291C',
      slogan: 'Im Lovin It'
    };
    const cocacola: LoopAdPreset = {
      id: 'cocacola',
      brand: 'Coca-Cola',
      emoji: '🥤',
      bgColor: '#F40009',
      fgColor: '#FFFFFF',
      slogan: 'Taste the Feeling'
    };
    const pepsi: LoopAdPreset = {
      id: 'pepsi',
      brand: 'Pepsi',
      emoji: '🔵',
      bgColor: '#004B93',
      fgColor: '#FFFFFF',
      slogan: 'Thats What I Like'
    };
    const apple: LoopAdPreset = {
      id: 'apple',
      brand: 'Apple',
      emoji: '🍎',
      bgColor: '#1C1C1E',
      fgColor: '#F5F5F7',
      slogan: 'Think Different'
    };
    const kfc: LoopAdPreset = {
      id: 'kfc',
      brand: 'KFC',
      emoji: '🍗',
      bgColor: '#E4002B',
      fgColor: '#FFFFFF',
      slogan: 'Finger Lickin Good'
    };
    const list: Array<LoopAdPreset> = [];
    list.push(nike);
    list.push(adidas);
    list.push(starbucks);
    list.push(mcdonalds);
    list.push(cocacola);
    list.push(pepsi);
    list.push(apple);
    list.push(kfc);
    return list;
  }

  static getById(id: string): LoopAdPreset | null {
    if (id.length === 0) {
      return null;
    }
    const presets = LoopAdCatalog.getPresets();
    for (let i = 0; i < presets.length; i++) {
      if (presets[i].id === id) {
        return presets[i];
      }
    }
    return null;
  }
}
