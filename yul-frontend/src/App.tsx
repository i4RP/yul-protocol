import { useState, useEffect, useCallback } from 'react'
import { usePrivy, useWallets } from '@privy-io/react-auth'
import { ethers } from 'ethers'
import './App.css'

import YULCorporationABI from './contracts/YULCorporation.json'
import YULShareTokenABI from './contracts/YULShareToken.json'
import YULGovernanceABI from './contracts/YULGovernance.json'
import YULTreasuryABI from './contracts/YULTreasury.json'
import YULDividendDistributorABI from './contracts/YULDividendDistributor.json'
import YULOfficerManagerABI from './contracts/YULOfficerManager.json'

type Page = 'dashboard' | 'governance' | 'shares' | 'treasury' | 'dividends' | 'officers'

interface CorporationInfo {
  name: string
  jurisdiction: string
  totalShares: string
  treasuryBalance: string
  isActive: boolean
  proposalCount: number
}

interface Proposal {
  id: number
  proposer: string
  proposalType: number
  description: string
  startBlock: number
  endBlock: number
  forVotes: string
  againstVotes: string
  abstainVotes: string
  executed: boolean
  cancelled: boolean
  state: number
}

const PROPOSAL_TYPES = ['General', 'Officer Election', 'Dividend Distribution', 'Treasury Spending', 'Parameter Change']
const PROPOSAL_STATES = ['Pending', 'Active', 'Defeated', 'Succeeded', 'Executed', 'Cancelled']
const STATE_COLORS: Record<number, string> = {
  0: 'bg-yellow-100 text-yellow-800',
  1: 'bg-blue-100 text-blue-800',
  2: 'bg-red-100 text-red-800',
  3: 'bg-green-100 text-green-800',
  4: 'bg-purple-100 text-purple-800',
  5: 'bg-gray-100 text-gray-800',
}

const DEFAULT_ADDRESSES = {
  corporation: '',
  shareToken: '',
  governance: '',
  treasury: '',
  dividendDistributor: '',
  officerManager: '',
}

function App() {
  const { login, logout, authenticated, user } = usePrivy()
  const { wallets } = useWallets()

  const [page, setPage] = useState<Page>('dashboard')
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false)
  const [account, setAccount] = useState<string>('')
  const [provider, setProvider] = useState<ethers.BrowserProvider | null>(null)
  const [signer, setSigner] = useState<ethers.Signer | null>(null)
  const [addresses, setAddresses] = useState(DEFAULT_ADDRESSES)
  const [corpInfo, setCorpInfo] = useState<CorporationInfo | null>(null)
  const [proposals, setProposals] = useState<Proposal[]>([])
  const [shareBalance, setShareBalance] = useState('0')
  const [votingPower, setVotingPower] = useState('0')
  const [isFounder, setIsFounder] = useState(false)
  const [loading, setLoading] = useState(false)
  const [txStatus, setTxStatus] = useState('')
  const [editAddresses, setEditAddresses] = useState(false)

  // Setup provider from Privy wallet
  useEffect(() => {
    const setupProvider = async () => {
      if (!authenticated || wallets.length === 0) {
        setProvider(null)
        setSigner(null)
        setAccount('')
        return
      }
      const wallet = wallets[0]
      try {
        const ethereumProvider = await wallet.getEthereumProvider()
        const ethersProvider = new ethers.BrowserProvider(ethereumProvider)
        const ethersSigner = await ethersProvider.getSigner()
        setProvider(ethersProvider)
        setSigner(ethersSigner)
        setAccount(wallet.address)
      } catch (err) {
        console.error('Failed to setup provider:', err)
      }
    }
    setupProvider()
  }, [authenticated, wallets])

  const loadCorporationInfo = useCallback(async () => {
    if (!provider || !addresses.corporation) return
    try {
      const corp = new ethers.Contract(addresses.corporation, YULCorporationABI, provider)
      const initialized = await corp.initialized()
      if (!initialized) { setCorpInfo(null); return }
      const info = await corp.corporationInfo()
      setCorpInfo({
        name: info._name,
        jurisdiction: info._jurisdiction,
        totalShares: ethers.formatEther(info._totalShares),
        treasuryBalance: ethers.formatEther(info._treasuryBalance),
        isActive: info._isActive,
        proposalCount: Number(info._proposalCount),
      })
      const founder = await corp.founder()
      setIsFounder(account.toLowerCase() === founder.toLowerCase())
    } catch (err) {
      console.error('Failed to load corporation info:', err)
    }
  }, [provider, addresses.corporation, account])

  const loadShareBalance = useCallback(async () => {
    if (!provider || !addresses.shareToken || !account) return
    try {
      const token = new ethers.Contract(addresses.shareToken, YULShareTokenABI, provider)
      const balance = await token.balanceOf(account)
      setShareBalance(ethers.formatEther(balance))
      const votes = await token.getVotes(account)
      setVotingPower(ethers.formatEther(votes))
    } catch (err) {
      console.error('Failed to load share balance:', err)
    }
  }, [provider, addresses.shareToken, account])

  const loadProposals = useCallback(async () => {
    if (!provider || !addresses.governance || !corpInfo) return
    try {
      const gov = new ethers.Contract(addresses.governance, YULGovernanceABI, provider)
      const count = corpInfo.proposalCount
      const proposalList: Proposal[] = []
      for (let i = count; i >= 1 && i > count - 10; i--) {
        const p = await gov.proposals(i)
        const state = await gov.state(i)
        proposalList.push({
          id: i, proposer: p.proposer, proposalType: Number(p.proposalType),
          description: p.description, startBlock: Number(p.startBlock), endBlock: Number(p.endBlock),
          forVotes: ethers.formatEther(p.forVotes), againstVotes: ethers.formatEther(p.againstVotes),
          abstainVotes: ethers.formatEther(p.abstainVotes), executed: p.executed, cancelled: p.cancelled,
          state: Number(state),
        })
      }
      setProposals(proposalList)
    } catch (err) {
      console.error('Failed to load proposals:', err)
    }
  }, [provider, addresses.governance, corpInfo])

  useEffect(() => {
    if (provider && account) { loadCorporationInfo(); loadShareBalance() }
  }, [provider, account, loadCorporationInfo, loadShareBalance])

  useEffect(() => {
    if (corpInfo && corpInfo.proposalCount > 0) loadProposals()
  }, [corpInfo, loadProposals])

  const showTx = (msg: string) => { setTxStatus(msg); setTimeout(() => setTxStatus(''), 5000) }

  const issueShares = async (to: string, amount: string, reason: string) => {
    if (!signer || !addresses.corporation) return
    setLoading(true)
    try {
      const corp = new ethers.Contract(addresses.corporation, YULCorporationABI, signer)
      const tx = await corp.issueShares(to, ethers.parseEther(amount), reason)
      await tx.wait()
      showTx('Shares issued successfully!')
      loadCorporationInfo(); loadShareBalance()
    } catch (err: unknown) { showTx('Error: ' + (err as Error).message) }
    setLoading(false)
  }

  const delegateVotes = async (delegatee: string) => {
    if (!signer || !addresses.shareToken) return
    setLoading(true)
    try {
      const token = new ethers.Contract(addresses.shareToken, YULShareTokenABI, signer)
      const tx = await token.delegate(delegatee)
      await tx.wait()
      showTx('Delegation successful!')
      loadShareBalance()
    } catch (err: unknown) { showTx('Error: ' + (err as Error).message) }
    setLoading(false)
  }

  const createProposal = async (proposalType: number, description: string, target: string, value: string, calldata: string) => {
    if (!signer || !addresses.governance) return
    setLoading(true)
    try {
      const gov = new ethers.Contract(addresses.governance, YULGovernanceABI, signer)
      const tx = await gov.propose(proposalType, description, [target], [ethers.parseEther(value || '0')], [calldata || '0x'])
      await tx.wait()
      showTx('Proposal created!')
      loadCorporationInfo()
    } catch (err: unknown) { showTx('Error: ' + (err as Error).message) }
    setLoading(false)
  }

  const castVote = async (proposalId: number, support: number) => {
    if (!signer || !addresses.governance) return
    setLoading(true)
    try {
      const gov = new ethers.Contract(addresses.governance, YULGovernanceABI, signer)
      const tx = await gov.castVote(proposalId, support)
      await tx.wait()
      showTx('Vote cast!')
      loadProposals()
    } catch (err: unknown) { showTx('Error: ' + (err as Error).message) }
    setLoading(false)
  }

  const executeProposal = async (proposalId: number) => {
    if (!signer || !addresses.governance) return
    setLoading(true)
    try {
      const gov = new ethers.Contract(addresses.governance, YULGovernanceABI, signer)
      const tx = await gov.execute(proposalId)
      await tx.wait()
      showTx('Proposal executed!')
      loadProposals(); loadCorporationInfo()
    } catch (err: unknown) { showTx('Error: ' + (err as Error).message) }
    setLoading(false)
  }

  const claimDividend = async (roundId: number) => {
    if (!signer || !addresses.dividendDistributor) return
    setLoading(true)
    try {
      const div = new ethers.Contract(addresses.dividendDistributor, YULDividendDistributorABI, signer)
      const tx = await div.claim(roundId)
      await tx.wait()
      showTx('Dividend claimed!')
    } catch (err: unknown) { showTx('Error: ' + (err as Error).message) }
    setLoading(false)
  }

  const navItems: { key: Page; label: string; icon: string }[] = [
    { key: 'dashboard', label: 'Dashboard', icon: '📊' },
    { key: 'shares', label: 'Shares', icon: '🪙' },
    { key: 'governance', label: 'Governance', icon: '🏛' },
    { key: 'treasury', label: 'Treasury', icon: '💰' },
    { key: 'dividends', label: 'Dividends', icon: '💎' },
    { key: 'officers', label: 'Officers', icon: '👔' },
  ]

  const displayName = user?.email?.address || user?.phone?.number || user?.google?.name || (account ? account.slice(0, 6) + '...' + account.slice(-4) : '')

  return (
    <div className="min-h-screen bg-gray-950 text-white">
      <header className="border-b border-gray-800 bg-gray-900/80 backdrop-blur-sm sticky top-0 z-50">
        <div className="max-w-7xl mx-auto flex items-center justify-between px-4 sm:px-6 py-3">
          <div className="flex items-center gap-2 sm:gap-3">
            <button onClick={() => setMobileMenuOpen(!mobileMenuOpen)} className="lg:hidden text-gray-400 hover:text-white p-1">
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M3 12h18M3 6h18M3 18h18"/></svg>
            </button>
            <div className="text-xl sm:text-2xl font-bold bg-gradient-to-r from-violet-400 to-indigo-400 bg-clip-text text-transparent">
              YUL Protocol
            </div>
            <span className="hidden sm:inline text-xs bg-violet-500/20 text-violet-300 px-2 py-0.5 rounded-full">
              営利法人
            </span>
          </div>
          <div className="flex items-center gap-2 sm:gap-4">
            {authenticated ? (
              <div className="flex items-center gap-2">
                <div className="hidden sm:flex items-center gap-2 bg-gray-800 rounded-lg px-3 py-1.5">
                  <div className="w-2 h-2 rounded-full bg-green-400 animate-pulse" />
                  <span className="text-sm font-mono text-gray-300 truncate max-w-32">{displayName}</span>
                </div>
                <div className="sm:hidden flex items-center gap-1 bg-gray-800 rounded-lg px-2 py-1.5">
                  <div className="w-2 h-2 rounded-full bg-green-400 animate-pulse" />
                  <span className="text-xs font-mono text-gray-300">{account ? account.slice(0, 4) + '...' : ''}</span>
                </div>
                <button onClick={logout} className="text-xs text-gray-500 hover:text-gray-300 px-2 py-1">
                  Logout
                </button>
              </div>
            ) : (
              <button onClick={login} className="flex items-center gap-2 bg-violet-600 hover:bg-violet-500 text-white px-3 sm:px-4 py-2 rounded-lg text-sm font-medium transition-colors">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M19 7V4a1 1 0 0 0-1-1H5a2 2 0 0 0 0 4h15a1 1 0 0 1 1 1v4h-3a2 2 0 0 0 0 4h3a1 1 0 0 0 1-1v-2a1 1 0 0 0-1-1"/><path d="M3 5v14a2 2 0 0 0 2 2h15a1 1 0 0 0 1-1v-4"/></svg>
                <span className="hidden sm:inline">Connect</span>
              </button>
            )}
          </div>
        </div>
      </header>

      <div className="max-w-7xl mx-auto flex gap-0 lg:gap-6 p-0 lg:p-6">
        {mobileMenuOpen && (
          <div className="fixed inset-0 bg-black/60 z-40 lg:hidden" onClick={() => setMobileMenuOpen(false)} />
        )}

        <nav className={[
          'fixed lg:static inset-y-0 left-0 z-50 w-64 lg:w-52 bg-gray-900 lg:bg-transparent',
          'transform transition-transform duration-200 ease-in-out',
          mobileMenuOpen ? 'translate-x-0' : '-translate-x-full lg:translate-x-0',
          'flex-shrink-0 pt-16 lg:pt-0 px-4 lg:px-0 overflow-y-auto',
        ].join(' ')}>
          <div className="space-y-1">
            {navItems.map((item) => (
              <button
                key={item.key}
                onClick={() => { setPage(item.key); setMobileMenuOpen(false) }}
                className={[
                  'w-full flex items-center gap-3 px-4 py-3 lg:py-2.5 rounded-lg text-sm font-medium transition-colors',
                  page === item.key
                    ? 'bg-violet-600/20 text-violet-300 border border-violet-500/30'
                    : 'text-gray-400 hover:bg-gray-800 hover:text-gray-200',
                ].join(' ')}
              >
                <span>{item.icon}</span>
                {item.label}
              </button>
            ))}
          </div>

          <div className="mt-8">
            <button
              onClick={() => setEditAddresses(!editAddresses)}
              className="w-full text-left px-4 py-2 text-xs text-gray-500 hover:text-gray-300 transition-colors"
            >
              {'Settings ' + (editAddresses ? '▲' : '▼')}
            </button>
            {editAddresses && (
              <div className="space-y-2 px-2 mt-2">
                {(Object.keys(addresses) as (keyof typeof addresses)[]).map((key) => (
                  <div key={key}>
                    <label className="text-xs text-gray-500 capitalize">{key}</label>
                    <input
                      type="text"
                      value={addresses[key]}
                      onChange={(e) => setAddresses({ ...addresses, [key]: e.target.value })}
                      className="w-full bg-gray-800 border border-gray-700 rounded px-2 py-1 text-xs font-mono text-gray-300 focus:border-violet-500 focus:outline-none"
                      placeholder="0x..."
                    />
                  </div>
                ))}
              </div>
            )}
          </div>
        </nav>

        <main className="flex-1 min-w-0 p-4 lg:p-0">
          {txStatus && (
            <div className={[
              'mb-4 p-3 rounded-lg text-sm',
              txStatus.startsWith('Error') ? 'bg-red-900/50 text-red-300 border border-red-700' : 'bg-green-900/50 text-green-300 border border-green-700',
            ].join(' ')}>
              {txStatus}
            </div>
          )}

          {!authenticated ? (
            <div className="flex flex-col items-center justify-center min-h-64 sm:h-96 gap-4 sm:gap-6 py-12">
              <div className="text-5xl sm:text-6xl">🔗</div>
              <h2 className="text-xl sm:text-2xl font-bold text-gray-300 text-center">Connect Your Wallet</h2>
              <p className="text-gray-500 text-center max-w-md text-sm sm:text-base px-4">
                Connect your Ethereum wallet to interact with the YUL Corporation protocol. Supports MetaMask, WalletConnect, email, and more.
              </p>
              <button
                onClick={login}
                className="flex items-center gap-2 bg-violet-600 hover:bg-violet-500 text-white px-6 py-3 rounded-lg font-medium transition-colors"
              >
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M19 7V4a1 1 0 0 0-1-1H5a2 2 0 0 0 0 4h15a1 1 0 0 1 1 1v4h-3a2 2 0 0 0 0 4h3a1 1 0 0 0 1-1v-2a1 1 0 0 0-1-1"/><path d="M3 5v14a2 2 0 0 0 2 2h15a1 1 0 0 0 1-1v-4"/></svg>
                Connect Wallet
              </button>
            </div>
          ) : !addresses.corporation ? (
            <div className="flex flex-col items-center justify-center min-h-64 sm:h-96 gap-4 sm:gap-6 py-12">
              <div className="text-5xl sm:text-6xl">📋</div>
              <h2 className="text-xl sm:text-2xl font-bold text-gray-300 text-center">Set Contract Addresses</h2>
              <p className="text-gray-500 text-center max-w-md text-sm sm:text-base px-4">
                Enter the deployed contract addresses in the sidebar to start interacting with the YUL Corporation.
              </p>
              <button
                onClick={() => { setEditAddresses(true); setMobileMenuOpen(true) }}
                className="bg-violet-600 hover:bg-violet-500 text-white px-6 py-3 rounded-lg font-medium transition-colors"
              >
                Configure Addresses
              </button>
            </div>
          ) : (
            <>
              {page === 'dashboard' && <DashboardPage corpInfo={corpInfo} shareBalance={shareBalance} votingPower={votingPower} isFounder={isFounder} proposals={proposals} />}
              {page === 'shares' && <SharesPage shareBalance={shareBalance} votingPower={votingPower} isFounder={isFounder} loading={loading} issueShares={issueShares} delegateVotes={delegateVotes} account={account} />}
              {page === 'governance' && <GovernancePage proposals={proposals} loading={loading} createProposal={createProposal} castVote={castVote} executeProposal={executeProposal} />}
              {page === 'treasury' && <TreasuryPage corpInfo={corpInfo} provider={provider} addresses={addresses} />}
              {page === 'dividends' && <DividendsPage loading={loading} claimDividend={claimDividend} provider={provider} addresses={addresses} account={account} />}
              {page === 'officers' && <OfficersPage provider={provider} addresses={addresses} />}
            </>
          )}
        </main>
      </div>
    </div>
  )
}

// ===== DASHBOARD PAGE =====
function DashboardPage({ corpInfo, shareBalance, votingPower, isFounder, proposals }: {
  corpInfo: CorporationInfo | null; shareBalance: string; votingPower: string; isFounder: boolean; proposals: Proposal[]
}) {
  return (
    <div className="space-y-4 sm:space-y-6">
      <h1 className="text-2xl sm:text-3xl font-bold">{corpInfo ? corpInfo.name : 'Corporation Dashboard'}</h1>

      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 sm:gap-4">
        <StatCard title="Total Shares" value={corpInfo ? Number(corpInfo.totalShares).toLocaleString() : '--'} subtitle="YUL" icon="🪙" />
        <StatCard title="Treasury" value={corpInfo ? Number(corpInfo.treasuryBalance).toFixed(4) : '--'} subtitle="ETH" icon="💰" />
        <StatCard title="Proposals" value={corpInfo ? String(corpInfo.proposalCount) : '--'} subtitle="total" icon="📝" />
        <StatCard title="Status" value={corpInfo?.isActive ? 'Active' : 'Inactive'} subtitle={corpInfo?.jurisdiction || ''} icon={corpInfo?.isActive ? 'ON' : 'OFF'} />
      </div>

      <div className="bg-gray-900 border border-gray-800 rounded-xl p-4 sm:p-6">
        <h2 className="text-base sm:text-lg font-semibold mb-3 sm:mb-4 text-gray-200">Your Position</h2>
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 sm:gap-4">
          <div className="bg-gray-800/50 rounded-lg p-3 sm:p-4">
            <div className="text-xs sm:text-sm text-gray-400">Share Balance</div>
            <div className="text-xl sm:text-2xl font-bold text-violet-300">{Number(shareBalance).toLocaleString()}</div>
            <div className="text-xs text-gray-500">YUL</div>
          </div>
          <div className="bg-gray-800/50 rounded-lg p-3 sm:p-4">
            <div className="text-xs sm:text-sm text-gray-400">Voting Power</div>
            <div className="text-xl sm:text-2xl font-bold text-indigo-300">{Number(votingPower).toLocaleString()}</div>
            <div className="text-xs text-gray-500">votes</div>
          </div>
          <div className="bg-gray-800/50 rounded-lg p-3 sm:p-4">
            <div className="text-xs sm:text-sm text-gray-400">Role</div>
            <div className="text-xl sm:text-2xl font-bold text-emerald-300">{isFounder ? 'Founder' : 'Shareholder'}</div>
            <div className="text-xs text-gray-500">{corpInfo?.jurisdiction}</div>
          </div>
        </div>
      </div>

      {proposals.length > 0 && (
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-4 sm:p-6">
          <h2 className="text-base sm:text-lg font-semibold mb-3 sm:mb-4 text-gray-200">Recent Proposals</h2>
          <div className="space-y-2 sm:space-y-3">
            {proposals.slice(0, 5).map((p) => (
              <div key={p.id} className="flex items-center justify-between bg-gray-800/50 rounded-lg p-2.5 sm:p-3">
                <div className="flex items-center gap-2 sm:gap-3 min-w-0">
                  <span className="text-gray-500 font-mono text-xs sm:text-sm">{'#' + p.id}</span>
                  <span className="text-gray-300 text-xs sm:text-sm truncate">{p.description}</span>
                </div>
                <span className={'px-2 py-0.5 rounded text-xs font-medium flex-shrink-0 ' + STATE_COLORS[p.state]}>
                  {PROPOSAL_STATES[p.state]}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  )
}

function StatCard({ title, value, subtitle, icon }: { title: string; value: string; subtitle: string; icon: string }) {
  return (
    <div className="bg-gray-900 border border-gray-800 rounded-xl p-3 sm:p-5">
      <div className="flex items-center justify-between mb-2 sm:mb-3">
        <span className="text-xs sm:text-sm text-gray-400">{title}</span>
        <span className="text-base sm:text-xl">{icon}</span>
      </div>
      <div className="text-lg sm:text-2xl font-bold text-white truncate">{value}</div>
      <div className="text-xs text-gray-500 mt-0.5 sm:mt-1">{subtitle}</div>
    </div>
  )
}

// ===== SHARES PAGE =====
function SharesPage({ shareBalance, votingPower, isFounder, loading, issueShares, delegateVotes, account }: {
  shareBalance: string; votingPower: string; isFounder: boolean; loading: boolean
  issueShares: (to: string, amount: string, reason: string) => Promise<void>
  delegateVotes: (delegatee: string) => Promise<void>; account: string
}) {
  const [issueTo, setIssueTo] = useState('')
  const [issueAmount, setIssueAmount] = useState('')
  const [issueReason, setIssueReason] = useState('')
  const [delegateTo, setDelegateTo] = useState('')

  return (
    <div className="space-y-4 sm:space-y-6">
      <h1 className="text-2xl sm:text-3xl font-bold">Share Management</h1>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 sm:gap-4">
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-4 sm:p-6">
          <div className="text-xs sm:text-sm text-gray-400 mb-1">Your Share Balance</div>
          <div className="text-2xl sm:text-3xl font-bold text-violet-300">{Number(shareBalance).toLocaleString()}</div>
          <div className="text-sm text-gray-500">YUL tokens</div>
        </div>
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-4 sm:p-6">
          <div className="text-xs sm:text-sm text-gray-400 mb-1">Voting Power</div>
          <div className="text-2xl sm:text-3xl font-bold text-indigo-300">{Number(votingPower).toLocaleString()}</div>
          <div className="text-sm text-gray-500">delegated votes</div>
        </div>
      </div>
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-4 sm:p-6">
        <h2 className="text-base sm:text-lg font-semibold mb-3 sm:mb-4 text-gray-200">Delegate Votes</h2>
        <p className="text-xs sm:text-sm text-gray-400 mb-3 sm:mb-4">Delegate your voting power to yourself or another address.</p>
        <div className="flex flex-col sm:flex-row gap-2 sm:gap-3">
          <input type="text" placeholder="Delegate address (or leave empty to self-delegate)" value={delegateTo}
            onChange={(e) => setDelegateTo(e.target.value)}
            className="flex-1 bg-gray-800 border border-gray-700 rounded-lg px-3 sm:px-4 py-2 text-sm text-gray-300 focus:border-violet-500 focus:outline-none" />
          <button onClick={() => delegateVotes(delegateTo || account)} disabled={loading}
            className="bg-indigo-600 hover:bg-indigo-500 disabled:bg-gray-700 text-white px-6 py-2 rounded-lg text-sm font-medium transition-colors whitespace-nowrap">
            {loading ? 'Processing...' : 'Delegate'}
          </button>
        </div>
      </div>
      {isFounder && (
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-4 sm:p-6">
          <h2 className="text-base sm:text-lg font-semibold mb-3 sm:mb-4 text-gray-200">Issue Shares</h2>
          <p className="text-xs sm:text-sm text-gray-400 mb-3 sm:mb-4">As the founder, you can issue new shares to shareholders.</p>
          <div className="space-y-2 sm:space-y-3">
            <input type="text" placeholder="Recipient address" value={issueTo} onChange={(e) => setIssueTo(e.target.value)}
              className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 sm:px-4 py-2 text-sm text-gray-300 focus:border-violet-500 focus:outline-none" />
            <div className="flex flex-col sm:flex-row gap-2 sm:gap-3">
              <input type="text" placeholder="Amount (e.g., 1000)" value={issueAmount} onChange={(e) => setIssueAmount(e.target.value)}
                className="flex-1 bg-gray-800 border border-gray-700 rounded-lg px-3 sm:px-4 py-2 text-sm text-gray-300 focus:border-violet-500 focus:outline-none" />
              <input type="text" placeholder="Reason" value={issueReason} onChange={(e) => setIssueReason(e.target.value)}
                className="flex-1 bg-gray-800 border border-gray-700 rounded-lg px-3 sm:px-4 py-2 text-sm text-gray-300 focus:border-violet-500 focus:outline-none" />
            </div>
            <button onClick={() => issueShares(issueTo, issueAmount, issueReason)} disabled={loading || !issueTo || !issueAmount}
              className="w-full sm:w-auto bg-violet-600 hover:bg-violet-500 disabled:bg-gray-700 text-white px-6 py-2 rounded-lg text-sm font-medium transition-colors">
              {loading ? 'Processing...' : 'Issue Shares'}
            </button>
          </div>
        </div>
      )}
    </div>
  )
}

// ===== GOVERNANCE PAGE =====
function GovernancePage({ proposals, loading, createProposal, castVote, executeProposal }: {
  proposals: Proposal[]; loading: boolean
  createProposal: (type: number, desc: string, target: string, value: string, calldata: string) => Promise<void>
  castVote: (proposalId: number, support: number) => Promise<void>
  executeProposal: (proposalId: number) => Promise<void>
}) {
  const [showCreate, setShowCreate] = useState(false)
  const [propType, setPropType] = useState(0)
  const [propDesc, setPropDesc] = useState('')
  const [propTarget, setPropTarget] = useState('')
  const [propValue, setPropValue] = useState('0')
  const [propCalldata, setPropCalldata] = useState('')

  return (
    <div className="space-y-4 sm:space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl sm:text-3xl font-bold">Governance</h1>
        <button onClick={() => setShowCreate(!showCreate)}
          className="bg-violet-600 hover:bg-violet-500 text-white px-3 sm:px-4 py-2 rounded-lg text-xs sm:text-sm font-medium transition-colors">
          {showCreate ? 'Cancel' : '+ New Proposal'}
        </button>
      </div>
      {showCreate && (
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-4 sm:p-6">
          <h2 className="text-base sm:text-lg font-semibold mb-3 sm:mb-4 text-gray-200">Create Proposal</h2>
          <div className="space-y-2 sm:space-y-3">
            <div>
              <label className="text-xs sm:text-sm text-gray-400 mb-1 block">Proposal Type</label>
              <select value={propType} onChange={(e) => setPropType(Number(e.target.value))}
                className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 sm:px-4 py-2 text-sm text-gray-300 focus:border-violet-500 focus:outline-none">
                {PROPOSAL_TYPES.map((t, i) => (<option key={i} value={i}>{t}</option>))}
              </select>
            </div>
            <div>
              <label className="text-xs sm:text-sm text-gray-400 mb-1 block">Description</label>
              <textarea value={propDesc} onChange={(e) => setPropDesc(e.target.value)} placeholder="Describe your proposal..."
                className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 sm:px-4 py-2 text-sm text-gray-300 focus:border-violet-500 focus:outline-none h-20 sm:h-24 resize-none" />
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-3 gap-2 sm:gap-3">
              <div>
                <label className="text-xs sm:text-sm text-gray-400 mb-1 block">Target Address</label>
                <input type="text" value={propTarget} onChange={(e) => setPropTarget(e.target.value)} placeholder="0x..."
                  className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 sm:px-4 py-2 text-sm text-gray-300 focus:border-violet-500 focus:outline-none" />
              </div>
              <div>
                <label className="text-xs sm:text-sm text-gray-400 mb-1 block">ETH Value</label>
                <input type="text" value={propValue} onChange={(e) => setPropValue(e.target.value)} placeholder="0"
                  className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 sm:px-4 py-2 text-sm text-gray-300 focus:border-violet-500 focus:outline-none" />
              </div>
              <div>
                <label className="text-xs sm:text-sm text-gray-400 mb-1 block">Calldata</label>
                <input type="text" value={propCalldata} onChange={(e) => setPropCalldata(e.target.value)} placeholder="0x (optional)"
                  className="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 sm:px-4 py-2 text-sm text-gray-300 focus:border-violet-500 focus:outline-none" />
              </div>
            </div>
            <button onClick={() => { createProposal(propType, propDesc, propTarget, propValue, propCalldata); setShowCreate(false) }}
              disabled={loading || !propDesc || !propTarget}
              className="w-full sm:w-auto bg-violet-600 hover:bg-violet-500 disabled:bg-gray-700 text-white px-6 py-2 rounded-lg text-sm font-medium transition-colors">
              {loading ? 'Processing...' : 'Submit Proposal'}
            </button>
          </div>
        </div>
      )}
      <div className="space-y-3 sm:space-y-4">
        {proposals.length === 0 ? (
          <div className="bg-gray-900 border border-gray-800 rounded-xl p-8 sm:p-12 text-center">
            <div className="text-3xl sm:text-4xl mb-3">📭</div>
            <div className="text-gray-400 text-sm sm:text-base">No proposals yet</div>
          </div>
        ) : (
          proposals.map((p) => (
            <div key={p.id} className="bg-gray-900 border border-gray-800 rounded-xl p-4 sm:p-5">
              <div className="flex flex-col sm:flex-row sm:items-start sm:justify-between mb-3 gap-2">
                <div className="min-w-0">
                  <div className="flex flex-wrap items-center gap-1.5 sm:gap-2 mb-1">
                    <span className="text-gray-500 font-mono text-xs sm:text-sm">{'#' + p.id}</span>
                    <span className={'px-2 py-0.5 rounded text-xs font-medium ' + STATE_COLORS[p.state]}>
                      {PROPOSAL_STATES[p.state]}
                    </span>
                    <span className="text-xs text-gray-500">{PROPOSAL_TYPES[p.proposalType]}</span>
                  </div>
                  <h3 className="text-gray-200 font-medium text-sm sm:text-base">{p.description}</h3>
                  <div className="text-xs text-gray-500 mt-1">
                    {'By ' + p.proposer.slice(0, 6) + '...' + p.proposer.slice(-4)}
                  </div>
                </div>
              </div>
              <div className="grid grid-cols-3 gap-2 sm:gap-4 mb-3">
                <VoteBar label="For" votes={p.forVotes} proposal={p} color="green" />
                <VoteBar label="Against" votes={p.againstVotes} proposal={p} color="red" />
                <VoteBar label="Abstain" votes={p.abstainVotes} proposal={p} color="gray" />
              </div>
              {p.state === 1 && (
                <div className="flex flex-wrap gap-2">
                  <button onClick={() => castVote(p.id, 1)} disabled={loading}
                    className="bg-green-600/20 hover:bg-green-600/30 text-green-400 px-3 sm:px-4 py-1.5 rounded-lg text-xs font-medium transition-colors border border-green-600/30">
                    Vote For
                  </button>
                  <button onClick={() => castVote(p.id, 0)} disabled={loading}
                    className="bg-red-600/20 hover:bg-red-600/30 text-red-400 px-3 sm:px-4 py-1.5 rounded-lg text-xs font-medium transition-colors border border-red-600/30">
                    Vote Against
                  </button>
                  <button onClick={() => castVote(p.id, 2)} disabled={loading}
                    className="bg-gray-600/20 hover:bg-gray-600/30 text-gray-400 px-3 sm:px-4 py-1.5 rounded-lg text-xs font-medium transition-colors border border-gray-600/30">
                    Abstain
                  </button>
                </div>
              )}
              {p.state === 3 && (
                <button onClick={() => executeProposal(p.id)} disabled={loading}
                  className="bg-purple-600 hover:bg-purple-500 text-white px-4 py-1.5 rounded-lg text-xs font-medium transition-colors">
                  Execute
                </button>
              )}
            </div>
          ))
        )}
      </div>
    </div>
  )
}

function VoteBar({ label, votes, proposal, color }: { label: string; votes: string; proposal: Proposal; color: string }) {
  const total = Number(proposal.forVotes) + Number(proposal.againstVotes) + Number(proposal.abstainVotes)
  const pct = total === 0 ? 0 : (Number(votes) / total) * 100
  const barColor = color === 'green' ? 'bg-green-500' : color === 'red' ? 'bg-red-500' : 'bg-gray-500'
  const textColor = color === 'green' ? 'text-green-400' : color === 'red' ? 'text-red-400' : 'text-gray-400'
  return (
    <div>
      <div className="text-xs text-gray-400 mb-1">{label}</div>
      <div className="bg-gray-800 rounded-full h-1.5 sm:h-2 overflow-hidden">
        <div className={barColor + ' h-full rounded-full'} style={{ width: pct + '%' }} />
      </div>
      <div className={'text-xs ' + textColor + ' mt-0.5'}>{Number(votes).toLocaleString()}</div>
    </div>
  )
}

// ===== TREASURY PAGE =====
function TreasuryPage({ corpInfo, provider, addresses }: {
  corpInfo: CorporationInfo | null; provider: ethers.BrowserProvider | null; addresses: typeof DEFAULT_ADDRESSES
}) {
  const [totalReceived, setTotalReceived] = useState('0')
  const [totalSpent, setTotalSpent] = useState('0')

  useEffect(() => {
    const load = async () => {
      if (!provider || !addresses.treasury) return
      try {
        const treasury = new ethers.Contract(addresses.treasury, YULTreasuryABI, provider)
        const received = await treasury.totalEthReceived()
        const spent = await treasury.totalEthSpent()
        setTotalReceived(ethers.formatEther(received))
        setTotalSpent(ethers.formatEther(spent))
      } catch (err) { console.error('Failed to load treasury info:', err) }
    }
    load()
  }, [provider, addresses.treasury])

  return (
    <div className="space-y-4 sm:space-y-6">
      <h1 className="text-2xl sm:text-3xl font-bold">Treasury</h1>
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 sm:gap-4">
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-4 sm:p-6">
          <div className="text-xs sm:text-sm text-gray-400 mb-1">Current Balance</div>
          <div className="text-2xl sm:text-3xl font-bold text-emerald-300">{corpInfo ? Number(corpInfo.treasuryBalance).toFixed(4) : '0'}</div>
          <div className="text-sm text-gray-500">ETH</div>
        </div>
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-4 sm:p-6">
          <div className="text-xs sm:text-sm text-gray-400 mb-1">Total Received</div>
          <div className="text-2xl sm:text-3xl font-bold text-blue-300">{Number(totalReceived).toFixed(4)}</div>
          <div className="text-sm text-gray-500">ETH</div>
        </div>
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-4 sm:p-6">
          <div className="text-xs sm:text-sm text-gray-400 mb-1">Total Spent</div>
          <div className="text-2xl sm:text-3xl font-bold text-orange-300">{Number(totalSpent).toFixed(4)}</div>
          <div className="text-sm text-gray-500">ETH</div>
        </div>
      </div>
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-4 sm:p-6">
        <h2 className="text-base sm:text-lg font-semibold mb-3 sm:mb-4 text-gray-200">Treasury Info</h2>
        <p className="text-xs sm:text-sm text-gray-400 mb-3 sm:mb-4">The treasury holds ETH and ERC20 tokens for the corporation. Spending requires governance approval.</p>
        <div className="bg-gray-800/50 rounded-lg p-3 sm:p-4">
          <div className="text-xs text-gray-500 mb-1">Treasury Address</div>
          <div className="font-mono text-xs sm:text-sm text-gray-300 break-all">{addresses.treasury || 'Not configured'}</div>
        </div>
      </div>
    </div>
  )
}

// ===== DIVIDENDS PAGE =====
function DividendsPage({ loading, claimDividend, provider, addresses, account }: {
  loading: boolean; claimDividend: (roundId: number) => Promise<void>
  provider: ethers.BrowserProvider | null; addresses: typeof DEFAULT_ADDRESSES; account: string
}) {
  const [currentRound, setCurrentRound] = useState(0)
  const [claimRoundId, setClaimRoundId] = useState('')
  const [unclaimedAmount, setUnclaimedAmount] = useState('0')
  const [checkRound, setCheckRound] = useState('')

  useEffect(() => {
    const load = async () => {
      if (!provider || !addresses.dividendDistributor) return
      try {
        const div = new ethers.Contract(addresses.dividendDistributor, YULDividendDistributorABI, provider)
        const round = await div.currentRoundId()
        setCurrentRound(Number(round))
      } catch (err) { console.error('Failed to load dividend info:', err) }
    }
    load()
  }, [provider, addresses.dividendDistributor])

  const checkUnclaimed = async () => {
    if (!provider || !addresses.dividendDistributor || !checkRound) return
    try {
      const div = new ethers.Contract(addresses.dividendDistributor, YULDividendDistributorABI, provider)
      const amount = await div.unclaimedDividend(Number(checkRound), account)
      setUnclaimedAmount(ethers.formatEther(amount))
    } catch (err) { console.error('Failed to check unclaimed:', err) }
  }

  return (
    <div className="space-y-4 sm:space-y-6">
      <h1 className="text-2xl sm:text-3xl font-bold">Dividends</h1>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 sm:gap-4">
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-4 sm:p-6">
          <div className="text-xs sm:text-sm text-gray-400 mb-1">Distribution Rounds</div>
          <div className="text-2xl sm:text-3xl font-bold text-violet-300">{currentRound}</div>
          <div className="text-sm text-gray-500">total rounds</div>
        </div>
        <div className="bg-gray-900 border border-gray-800 rounded-xl p-4 sm:p-6">
          <div className="text-xs sm:text-sm text-gray-400 mb-1">Distribution Method</div>
          <div className="text-lg sm:text-xl font-bold text-indigo-300">Pull-based (Claim)</div>
          <div className="text-sm text-gray-500">Proportional to share ownership</div>
        </div>
      </div>
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-4 sm:p-6">
        <h2 className="text-base sm:text-lg font-semibold mb-3 sm:mb-4 text-gray-200">Check Unclaimed Dividends</h2>
        <div className="flex flex-col sm:flex-row gap-2 sm:gap-3 mb-3 sm:mb-4">
          <input type="number" placeholder="Round ID" value={checkRound} onChange={(e) => setCheckRound(e.target.value)}
            className="flex-1 bg-gray-800 border border-gray-700 rounded-lg px-3 sm:px-4 py-2 text-sm text-gray-300 focus:border-violet-500 focus:outline-none" />
          <button onClick={checkUnclaimed}
            className="bg-indigo-600 hover:bg-indigo-500 text-white px-6 py-2 rounded-lg text-sm font-medium transition-colors whitespace-nowrap">
            Check
          </button>
        </div>
        {unclaimedAmount !== '0' && (
          <div className="bg-emerald-900/20 border border-emerald-700/30 rounded-lg p-3 sm:p-4">
            <div className="text-xs sm:text-sm text-emerald-400">Unclaimed: <strong>{unclaimedAmount + ' ETH'}</strong></div>
          </div>
        )}
      </div>
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-4 sm:p-6">
        <h2 className="text-base sm:text-lg font-semibold mb-3 sm:mb-4 text-gray-200">Claim Dividend</h2>
        <div className="flex flex-col sm:flex-row gap-2 sm:gap-3">
          <input type="number" placeholder="Round ID" value={claimRoundId} onChange={(e) => setClaimRoundId(e.target.value)}
            className="flex-1 bg-gray-800 border border-gray-700 rounded-lg px-3 sm:px-4 py-2 text-sm text-gray-300 focus:border-violet-500 focus:outline-none" />
          <button onClick={() => claimDividend(Number(claimRoundId))} disabled={loading || !claimRoundId}
            className="bg-violet-600 hover:bg-violet-500 disabled:bg-gray-700 text-white px-6 py-2 rounded-lg text-sm font-medium transition-colors whitespace-nowrap">
            {loading ? 'Processing...' : 'Claim'}
          </button>
        </div>
      </div>
    </div>
  )
}

// ===== OFFICERS PAGE =====
function OfficersPage({ provider, addresses }: {
  provider: ethers.BrowserProvider | null; addresses: typeof DEFAULT_ADDRESSES
}) {
  const [ceo, setCeo] = useState<string>('')
  const [cfo, setCfo] = useState<string>('')
  const [secretary, setSecretary] = useState<string>('')
  const [directors, setDirectors] = useState<string[]>([])

  useEffect(() => {
    const load = async () => {
      if (!provider || !addresses.officerManager) return
      try {
        const mgr = new ethers.Contract(addresses.officerManager, YULOfficerManagerABI, provider)
        const ceoRole = await mgr.CEO_ROLE()
        const cfoRole = await mgr.CFO_ROLE()
        const secRole = await mgr.SECRETARY_ROLE()
        const ceoAddr = await mgr.officerOf(ceoRole)
        const cfoAddr = await mgr.officerOf(cfoRole)
        const secAddr = await mgr.officerOf(secRole)
        setCeo(ceoAddr); setCfo(cfoAddr); setSecretary(secAddr)
        const dirs = await mgr.getDirectors()
        setDirectors(dirs)
      } catch (err) { console.error('Failed to load officers:', err) }
    }
    load()
  }, [provider, addresses.officerManager])

  const formatAddr = (addr: string) => {
    if (!addr || addr === ethers.ZeroAddress) return 'Vacant'
    return addr.slice(0, 6) + '...' + addr.slice(-4)
  }

  return (
    <div className="space-y-4 sm:space-y-6">
      <h1 className="text-2xl sm:text-3xl font-bold">Officers & Directors</h1>
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-4 sm:p-6">
        <h2 className="text-base sm:text-lg font-semibold mb-3 sm:mb-4 text-gray-200">Corporate Officers</h2>
        <div className="space-y-2 sm:space-y-3">
          <OfficerCard title="CEO" fullTitle="Chief Executive Officer" address={formatAddr(ceo)} icon="👤" />
          <OfficerCard title="CFO" fullTitle="Chief Financial Officer" address={formatAddr(cfo)} icon="💼" />
          <OfficerCard title="Secretary" fullTitle="Secretary" address={formatAddr(secretary)} icon="📋" />
        </div>
      </div>
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-4 sm:p-6">
        <h2 className="text-base sm:text-lg font-semibold mb-3 sm:mb-4 text-gray-200">Board of Directors</h2>
        {directors.length === 0 ? (
          <div className="text-center py-6 sm:py-8 text-gray-500 text-sm">No directors appointed</div>
        ) : (
          <div className="space-y-2">
            {directors.map((dir, i) => (
              <div key={i} className="flex items-center justify-between bg-gray-800/50 rounded-lg p-2.5 sm:p-3">
                <div className="flex items-center gap-2 sm:gap-3 min-w-0">
                  <span className="text-gray-500 text-xs sm:text-sm">{'#' + (i + 1)}</span>
                  <span className="font-mono text-xs sm:text-sm text-gray-300 truncate">{dir}</span>
                </div>
                <span className="text-xs bg-blue-500/20 text-blue-300 px-2 py-0.5 rounded flex-shrink-0">Director</span>
              </div>
            ))}
          </div>
        )}
      </div>
      <div className="bg-gray-900 border border-gray-800 rounded-xl p-4 sm:p-6">
        <h2 className="text-base sm:text-lg font-semibold mb-2 sm:mb-3 text-gray-200">How to Manage Officers</h2>
        <p className="text-xs sm:text-sm text-gray-400">
          Officers and directors are appointed or removed through governance proposals. Create a proposal of type &quot;Officer Election&quot; in the Governance tab.
        </p>
      </div>
    </div>
  )
}

function OfficerCard({ title, fullTitle, address, icon }: { title: string; fullTitle: string; address: string; icon: string }) {
  return (
    <div className="flex items-center justify-between bg-gray-800/50 rounded-lg p-3 sm:p-4">
      <div className="flex items-center gap-2 sm:gap-3">
        <span className="text-xl sm:text-2xl">{icon}</span>
        <div>
          <div className="text-xs sm:text-sm font-medium text-gray-200">
            <span className="sm:hidden">{title}</span>
            <span className="hidden sm:inline">{fullTitle}</span>
          </div>
          <div className="text-xs font-mono text-gray-400">{address}</div>
        </div>
      </div>
      <span className={'text-xs px-2 py-0.5 rounded ' + (address === 'Vacant' ? 'bg-gray-700 text-gray-400' : 'bg-green-500/20 text-green-300')}>
        {address === 'Vacant' ? 'Vacant' : 'Active'}
      </span>
    </div>
  )
}

export default App
