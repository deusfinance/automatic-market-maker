# Be name khoda

import matplotlib.pyplot as plt


class Bancor:
    def __init__(self):
        self.dots = []

        self.supply = 966434.5151219232
        self.firstSupply = 966434.5151219232

        self.reserve = 1355.78619979048
        self.firstReserve = 1355.78619979048

        self.cw = 0.4

        self.reserveShiftAmount = self.reserve * (1 - self.cw)

        self.maxDaoShare = 0.15
        self.daoBalance = 0
        self.daoTargetBalance = 500

    def daoShare(self):
        if self.daoBalance >= self.daoTargetBalance:
            return 0
        return self.maxDaoShare * (1 - (self.daoBalance / self.daoTargetBalance))

    def price(self):
        if self.supply > self.firstSupply:
            result = (self.reserve - self.reserveShiftAmount) / (self.supply * self.cw)
            return result
        else:
            return self.reserve / self.supply

    def calculatePurchaseReturn(self, etherAmount):
        etherAmount = etherAmount * (1 - self.daoShare())

        tokenAmount = 0
        if self.supply < self.firstSupply:
            exteraEtherAmount = self.reserve + etherAmount - self.firstReserve
            if exteraEtherAmount > 0:
                tokenAmount = self.firstSupply - self.supply
                result = ((exteraEtherAmount+self.firstReserve-self.reserveShiftAmount) /
                          (self.firstReserve-self.reserveShiftAmount))**(self.cw)
                baseSupply = self.firstSupply
            else:
                result = (etherAmount+self.reserve)/self.reserve
                baseSupply = self.supply

        else:
            baseSupply = self.supply
            result = ((etherAmount+self.reserve-self.reserveShiftAmount) /
                      (self.reserve-self.reserveShiftAmount))**(self.cw)

        new_supply = baseSupply*result
        tokenAmount += new_supply-baseSupply

        return tokenAmount

    def calculateSaleReturn(self, tokenAmount):
        if self.supply > self.firstSupply:
            exteraTokenAmount = self.firstSupply - (self.supply - tokenAmount)
            if exteraTokenAmount > 0:
                etherAmount = self.reserve - self.firstReserve

                etherAmount += self.firstReserve * \
                    (exteraTokenAmount/self.firstSupply)

            else:
                etherAmount = (self.reserve-self.reserveShiftAmount) * \
                    (1 - ((1 - tokenAmount/self.supply)**(1/self.cw)))

        else:
            etherAmount = self.reserve * (tokenAmount/self.supply)

        return etherAmount

    def buy(self, etherAmount):
        reserveEtherAmount = etherAmount * (1 - self.daoShare())
        daoEtherAmount = etherAmount * self.daoShare()

        tokenAmount = self.calculatePurchaseReturn(etherAmount)

        self.supply += tokenAmount

        self.reserve += reserveEtherAmount
        self.daoBalance += daoEtherAmount

        self.dots += [(self.supply, self.price())]
        return tokenAmount

    def sell(self, tokenAmount):
        etherAmount = self.calculateSaleReturn(tokenAmount)

        self.supply -= tokenAmount

        self.reserve -= (etherAmount)

        self.dots += [(self.supply, self.price())]
        return etherAmount

    def plot(self, style='r+'):
        supplies = [dot[0] for dot in self.dots]
        prices = [dot[1] for dot in self.dots]
        plt.plot(supplies, prices, style)

    def clearDots(self):
        self.dots = []


def test():
    bancor = Bancor()

    bought = []
    eth = 3333

    # bancor.buy(eth)
    # bancor.buy(eth)

    # print(bancor.supply, bancor.reserve)
    # token = bancor.buy(eth)
    # print(token)

    for i in range(20):
        print(i)
        token = bancor.buy(eth)
        bought.append(token)
        print('buy', token, eth, bancor.daoBalance)
    bancor.plot('b+')
    bancor.clearDots()

    # bancor.plot('b+')
    plt.show()


test()

# Dar panah khoda
